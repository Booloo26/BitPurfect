import AppKit
import Foundation
import MediaRemoteAdapter
import SimplyCoreAudio

/// Orchestrates automatic switching: watches for Apple Music track changes, waits for
/// coreaudiod to log the new track's real decoded format, then matches the output
/// device's nominal sample rate to it. Detection always runs (even with auto-switch off)
/// so the panel can still show an accurate "here's what's not lining up" verdict.
///
/// It also owns the DAC keep-awake stream, which follows the same target device.
final class SwitchingEngine {
    private let audio: AudioDeviceController
    private let formatStream = AppleMusicFormatStream()
    private let watcher = NowPlayingWatcher()
    private let keepAwake = DACKeepAwake()

    /// Detection is push-based — `AppleMusicFormatStream` reports a format the moment Music
    /// logs it — so there is no polling schedule here at all. The only timer left is the one
    /// below, which decides when to stop *expecting* a format.

    /// How long a track may play with nothing ever detected before the panel says so. Only
    /// armed while no format is known at all: once one is in hand it carries across tracks,
    /// because Music reuses a decoder (and logs nothing) for runs of same-format tracks.
    private static let detectionDeadline: TimeInterval = 12.0

    private let isEnabledKey = "autoSwitchEnabled"

    /// Bumped on every track change so a deadline armed for a previous track can't fire.
    private var detectionGeneration = 0

    /// Long enough to swallow CoreAudio's burst of device notifications, short enough that a
    /// rate changed behind our back is corrected before a listener would notice.
    private static let reapplyDebounce: TimeInterval = 0.2
    private var reapplyWorkItem: DispatchWorkItem?
    /// Set once detection gives up on a track: Music is playing, but it never logged a
    /// lossless decode for it (a lossy stream, typically).
    private var formatSearchExhausted = false
    private var notificationTokens: [NSObjectProtocol] = []
    private var workspaceTokens: [NSObjectProtocol] = []

    private(set) var currentTrackTitle: String?
    private(set) var currentTrackArtist: String?
    private(set) var lastFormat: DetectedFormat?
    private(set) var currentSource: NowPlayingSource = .stopped

    /// Where non-Apple-Music audio gets parked. 48 kHz is what video, web audio and system
    /// sound are authored at, so sitting there means the common case isn't resampled either.
    /// The depth is a preference rather than a promise — see `applyFallback`.
    private static let fallbackRate: Double = 48_000
    private static let fallbackBitDepth = 24

    var isEnabled = UserDefaults.standard.object(forKey: "autoSwitchEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: isEnabledKey)
            applyForCurrentState()
            onStateChanged?()
        }
    }

    /// Mirrors `AudioDeviceController.fallbackForOtherAppsEnabled`, re-evaluating immediately so
    /// turning it on while a video is playing takes effect there and then.
    var isFallbackEnabled: Bool {
        get { audio.fallbackForOtherAppsEnabled }
        set {
            audio.fallbackForOtherAppsEnabled = newValue
            applyForCurrentState()
            onStateChanged?()
        }
    }

    /// Mirrors `AudioDeviceController.keepAwakeEnabled`, starting or tearing down the
    /// silent stream as it flips.
    var isKeepAwakeEnabled: Bool {
        get { audio.keepAwakeEnabled }
        set {
            audio.keepAwakeEnabled = newValue
            updateKeepAwake()
            onStateChanged?()
        }
    }

    /// Fires whenever anything that could change what the panel shows happens.
    var onStateChanged: (() -> Void)?

    init(audio: AudioDeviceController) {
        self.audio = audio
        watcher.onSourceChanged = { [weak self] source in
            self?.handleSourceChanged(source)
        }
        formatStream.onFormat = { [weak self] format in
            self?.handleFormatDetected(format)
        }
    }

    func start() {
        watcher.start()
        observeDeviceChanges()
        formatStream.start()
        updateKeepAwake()
    }

    func stop() {
        watcher.stop()
        formatStream.stop()
        // Invalidates any armed detection deadline.
        detectionGeneration += 1
        reapplyWorkItem?.cancel()
        reapplyWorkItem = nil
        keepAwake.stop()
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens.removeAll()
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceTokens.removeAll()
    }

    /// A DAC that appears or disappears mid-session has to pick up both the current
    /// track's rate and the keep-awake stream without waiting for the next track.
    ///
    /// `deviceNominalSampleRateDidChange` is what makes holding the rate a guarantee rather
    /// than an accident. Without it the rate was only re-asserted because CoreAudio happens to
    /// republish the device list when a rate changes — which fires for the default device but
    /// not for a device this app is merely pinned to, so a pinned DAC silently kept whatever
    /// rate Audio MIDI Setup or another app had left it on.
    private func observeDeviceChanges() {
        let names: [Notification.Name] = [
            .defaultOutputDeviceChanged,
            .deviceListChanged,
            .deviceNominalSampleRateDidChange
        ]
        for name in names {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.scheduleReapply()
            }
            notificationTokens.append(token)
        }

        // Sleep takes the whole audio stack down with it, so the IOProc handle we're still
        // holding on wake is stale — and a DAC coming back from a dead USB link is exactly
        // when it pops. Rebuild the stream from scratch instead of trusting it.
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let wakeToken = workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.keepAwake.stop()
            self.reapplyToCurrentDevice()
        }
        workspaceTokens.append(wakeToken)
    }

    // MARK: - Detection

    private func handleSourceChanged(_ source: NowPlayingSource) {
        currentSource = source

        switch source {
        case .stopped, .otherApp:
            // `lastFormat` is deliberately kept through both. Pausing does not unload the track,
            // and Music logs a decoder line only when it *creates* a decoder: resuming reuses the
            // existing one and logs nothing at all. Clearing the format here left nothing to
            // detect and nothing to re-detect, so a pause/resume stranded the panel until some
            // later track happened to build a new decoder.
            detectionGeneration += 1
            currentTrackTitle = nil
            currentTrackArtist = nil

        case .appleMusic(let title, let artist):
            currentTrackTitle = title
            currentTrackArtist = artist
            // Same reasoning across a track change: a run of tracks in one format logs a line
            // only for the first. No new line means "same format as before", not "not lossless".
            formatSearchExhausted = false

            if lastFormat == nil {
                // Nothing in hand, and the stream stays silent for a reused decoder — so the only
                // way to learn the format is to read what was already logged. Covers launching
                // while paused, and returning from a lossy stretch.
                formatStream.reseed()
            }
            armDetectionDeadline()
        }

        applyForCurrentState()
        updateKeepAwake()
        onStateChanged?()
    }

    /// A format arriving from the stream — the only way one ever arrives now.
    private func handleFormatDetected(_ format: DetectedFormat) {
        // Only ever move forward: the launch backfill can land after a live line has already
        // reported something newer.
        if let known = lastFormat, format.date < known.date { return }

        // Music writes the decoder line twice, milliseconds apart, so every track change
        // arrived here twice — doing the work, and rebuilding the panel, both times. An
        // identical repeat carries no new information; a device that has drifted off this
        // format is the rate-change observer's job, not this one's.
        if let known = lastFormat,
           known.sampleRate == format.sampleRate,
           known.bitDepth == format.bitDepth {
            return
        }

        lastFormat = format
        formatSearchExhausted = false
        applyForCurrentState()
        onStateChanged?()
    }

    /// Lets the panel stop saying "reading the stream" for a track that will never report a
    /// rate — a lossy stream logs no decoder line at all. Armed only while nothing is known,
    /// since a carried-over format is the correct answer for a same-format run of tracks.
    private func armDetectionDeadline() {
        detectionGeneration += 1
        let generation = detectionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.detectionDeadline) { [weak self] in
            guard let self, generation == self.detectionGeneration, self.lastFormat == nil else { return }
            self.formatSearchExhausted = true
            self.onStateChanged?()
        }
    }

    // MARK: - Action

    /// A manually forced rate wins over everything else, matching the design's `resolve()`
    /// priority (forced > auto-follow > left alone).
    private func resolvedForcedRate(deviceRates: [Double]) -> Double? {
        guard let forced = audio.forcedRate else { return nil }
        return deviceRates.contains { abs($0 - forced) < 0.5 } ? forced : nil
    }

    /// Decides what the device should be running at right now and puts it there.
    ///
    /// Priority, highest first: a rate the user pinned by hand, then Apple Music's own rate,
    /// then the 48 kHz fallback for anything else that's playing. With nothing playing the rate
    /// is left alone, so pausing doesn't make the DAC re-lock.
    private func applyForCurrentState() {
        guard let device = audio.targetDevice else { return }
        let deviceRates = audio.availableSampleRates(of: device)

        if let forced = resolvedForcedRate(deviceRates: deviceRates) {
            setRateIfNeeded(forced, on: device)
            return
        }

        switch currentSource {
        case .appleMusic:
            guard isEnabled,
                  let format = lastFormat,
                  let best = audio.bestSupportedRate(for: format.sampleRate, on: device) else { return }
            setRateIfNeeded(best, on: device)

        case .otherApp:
            guard audio.fallbackForOtherAppsEnabled else { return }
            applyFallback(on: device)

        case .stopped:
            return
        }
    }

    /// Parks the device at the fallback rate, and asks for the fallback bit depth as a bonus.
    ///
    /// The depth genuinely is a bonus: a device only offers what its driver publishes, and many
    /// expose nothing but a 32-bit container at 48 kHz. When the exact pair isn't available the
    /// rate still moves and the depth is left as it was, which is the honest outcome — better
    /// than refusing to switch at all over a depth the hardware was never going to accept.
    private func applyFallback(on device: AudioDevice) {
        let rate = audio.bestSupportedRate(for: Self.fallbackRate, on: device) ?? Self.fallbackRate
        setRateIfNeeded(rate, on: device)
        audio.setPhysicalFormat(sampleRate: rate, bitDepth: Self.fallbackBitDepth, on: device)
    }

    private func setRateIfNeeded(_ target: Double, on device: AudioDevice) {
        if let current = audio.currentSampleRate(of: device), abs(current - target) < 0.5 { return }
        audio.setSampleRate(target, on: device)
    }

    /// Collapses a burst of device notifications into one pass. A single rate change makes
    /// CoreAudio republish the device list roughly nine times inside 1.5s; without this, each
    /// one drove a full re-evaluation, keep-awake check and panel rebuild.
    private func scheduleReapply() {
        reapplyWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reapplyWorkItem = nil
            self?.reapplyToCurrentDevice()
        }
        reapplyWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reapplyDebounce, execute: work)
    }

    /// Re-evaluates the current track against the (possibly newly picked) target device or
    /// forced rate — call after the user changes which device BitPurfect targets, or pins/clears a rate.
    ///
    /// Safe to reach from a rate-change notification: our own write fires one too, but
    /// `applyForCurrentState` stops as soon as the device already sits on the target, so it
    /// settles rather than looping.
    func reapplyToCurrentDevice() {
        applyForCurrentState()
        updateKeepAwake()
        onStateChanged?()
    }

    // MARK: - Keep awake

    /// The silent stream runs whenever the target device is an outboard DAC and the user
    /// hasn't turned it off, and it emits pure zeros for as long as Music is streaming so
    /// a bit-perfect path stays bit perfect.
    private func updateKeepAwake() {
        keepAwake.isSourcePlaying = currentSource.isPlaying

        guard audio.keepAwakeEnabled,
              let device = audio.targetDevice,
              audio.isAntiPopTarget(device) else {
            keepAwake.stop()
            return
        }
        keepAwake.start(on: device)
    }

    /// The design's anti-pop row, gated on `dacConnected`. The hint reports what's actually
    /// happening rather than what was asked for, so a stream that failed to open reads as a
    /// warning instead of a promise.
    private func antiPopState(for device: AudioDevice) -> PanelDisplayState.AntiPop? {
        guard audio.isAntiPopTarget(device) else { return nil }

        let isEnabled = audio.keepAwakeEnabled
        let isHolding = keepAwake.isRunning
        let hint: String
        if isEnabled, isHolding {
            hint = "Silent stream keeps \(device.name) awake whenever it's connected — between tracks, on pause, and while idle."
        } else if isEnabled {
            hint = "Couldn't open a silent stream on \(device.name) — it may still click when its output stage powers down."
        } else {
            hint = "Off — expect a click when \(device.name) powers its output stage back up."
        }

        return PanelDisplayState.AntiPop(isEnabled: isEnabled, isHolding: isHolding, hint: hint)
    }

    // MARK: - Display

    func currentDisplayState() -> PanelDisplayState? {
        guard let device = audio.targetDevice else { return nil }

        let currentRate = audio.currentSampleRate(of: device)
        let deviceRates = audio.availableSampleRates(of: device)
        let deviceBits = audio.physicalBitDepth(of: device)
        let antiPop = antiPopState(for: device)

        if case .otherApp(let appName) = currentSource {
            return otherAppState(
                appName: appName,
                device: device,
                currentRate: currentRate,
                deviceBits: deviceBits,
                antiPop: antiPop
            )
        }

        let isPlaying = currentSource.isPlaying

        guard isPlaying, let format = lastFormat else {
            return waitingState(
                device: device,
                currentRate: currentRate,
                deviceBits: deviceBits,
                antiPop: antiPop
            )
        }

        let forced = resolvedForcedRate(deviceRates: deviceRates)
        let deviceSupportsExact = deviceRates.contains { abs($0 - format.sampleRate) < 0.5 }

        let outRate: Double
        if let forced {
            outRate = forced
        } else if isEnabled, deviceSupportsExact {
            outRate = format.sampleRate
        } else {
            outRate = currentRate ?? audio.bestSupportedRate(for: format.sampleRate, on: device) ?? format.sampleRate
        }

        let locked = abs(outRate - format.sampleRate) < 0.5
        let outBits = locked ? format.bitDepth : (deviceBits ?? format.bitDepth)
        let formatLabel = format.sampleRate > 48000 ? "Hi-Res Lossless" : "Lossless"

        let verdict: String
        if let forced, !locked {
            verdict = "You pinned it to \(PanelDisplayState.fmt(forced)) kHz, so \(PanelDisplayState.fmt(format.sampleRate)) is getting converted on the way out. Tap Auto to undo."
        } else if locked {
            verdict = "Untouched. What left the studio is what hits the DAC."
        } else if !isEnabled {
            verdict = "Auto-switch is off, so macOS is squashing \(PanelDisplayState.fmt(format.sampleRate)) into \(PanelDisplayState.fmt(outRate)). Your call, but ouch."
        } else if deviceRates.isEmpty {
            verdict = "\(device.name) didn't report any supported rates."
        } else if deviceRates.count == 1 {
            verdict = "\(device.name) only speaks \(PanelDisplayState.fmt(outRate)) kHz. Everything gets resampled on the way in."
        } else {
            verdict = "\(PanelDisplayState.fmt(format.sampleRate)) kHz is past what \(device.name) can take, so it's being resampled to \(PanelDisplayState.fmt(outRate))."
        }

        return PanelDisplayState(
            status: locked ? .locked : .resampled,
            menubarLabel: "\(PanelDisplayState.fmt(outRate))k",
            outRateStr: PanelDisplayState.fmt(outRate),
            outBits: outBits,
            format: formatLabel,
            verdict: verdict,
            deviceName: device.name,
            autoOn: isEnabled && forced == nil,
            isSourcePlaying: isPlaying,
            sourceLabel: "Apple Music",
            antiPop: antiPop
        )
    }

    /// Covers both of the states where there's no decoded format to report: Music isn't
    /// playing at all, and the ~1-2s after a track starts while we wait for coreaudiod to
    /// log what it's decoding.
    /// Something other than Apple Music is playing. There's no source rate to be faithful to
    /// here — the honest thing is to say who has the audio and where the device is sitting.
    private func otherAppState(
        appName: String,
        device: AudioDevice,
        currentRate: Double?,
        deviceBits: Int?,
        antiPop: PanelDisplayState.AntiPop?
    ) -> PanelDisplayState {
        let rateStr = currentRate.map(PanelDisplayState.fmt) ?? "—"
        let forced = resolvedForcedRate(deviceRates: audio.availableSampleRates(of: device))

        let verdict: String
        if let forced {
            verdict = "\(appName) is playing, and you've pinned the output to \(PanelDisplayState.fmt(forced)) kHz, so that's where it stays."
        } else if audio.fallbackForOtherAppsEnabled {
            verdict = "\(appName) is playing, so the DAC is parked at \(rateStr) kHz — the rate most video and web audio is made at. Apple Music takes it back on the next track."
        } else {
            verdict = "\(appName) is playing. Fallback is off, so the DAC is left at \(rateStr) kHz, whatever the last track needed."
        }

        return PanelDisplayState(
            status: .otherSource,
            menubarLabel: currentRate.map { "\(PanelDisplayState.fmt($0))k" } ?? "—",
            outRateStr: rateStr,
            outBits: deviceBits ?? 0,
            format: audio.fallbackForOtherAppsEnabled && forced == nil ? "Fallback" : "Not Apple Music",
            verdict: verdict,
            deviceName: device.name,
            autoOn: isEnabled && forced == nil,
            isSourcePlaying: true,
            sourceLabel: appName,
            antiPop: antiPop
        )
    }

    private func waitingState(
        device: AudioDevice,
        currentRate: Double?,
        deviceBits: Int?,
        antiPop: PanelDisplayState.AntiPop?
    ) -> PanelDisplayState {
        let rateStr = currentRate.map(PanelDisplayState.fmt) ?? "—"
        let isPlaying = currentSource.isPlaying
        let unreadable = isPlaying && formatSearchExhausted

        let verdict: String
        if unreadable {
            verdict = "Apple Music is playing, but nothing lossless came through — so there's no source rate to match and the DAC holds at \(rateStr) kHz."
        } else if isPlaying {
            verdict = "Apple Music just started something — reading the stream to see what it's decoding."
        } else if let currentRate {
            verdict = "Apple Music isn't playing, so the DAC is parked at \(PanelDisplayState.fmt(currentRate)) kHz. It'll follow the next track."
        } else {
            verdict = "Play something in Apple Music and this will show whether it's reaching your DAC untouched."
        }

        return PanelDisplayState(
            status: .idle,
            menubarLabel: currentRate.map { "\(PanelDisplayState.fmt($0))k" } ?? "—",
            outRateStr: rateStr,
            outBits: deviceBits ?? 0,
            format: unreadable ? "No lossless stream" : isPlaying ? "Reading the stream" : "No stream",
            verdict: verdict,
            deviceName: device.name,
            autoOn: isEnabled && audio.forcedRate == nil,
            isSourcePlaying: isPlaying,
            sourceLabel: isPlaying ? "Apple Music" : "Apple Music · idle",
            antiPop: antiPop
        )
    }

}
