import Foundation

struct DetectedFormat: Equatable {
    let sampleRate: Double
    let bitDepth: Int
    let date: Date
}

/// Reports the real sample rate/bit depth of whatever Apple Music is decoding, by watching
/// the one line Music logs when it builds an ALAC decoder:
///   ACAppleLosslessDecoder.cpp:681 (0x...) Input format: 2 ch, 48000 Hz, alac (0x00000003)
///   from 24-bit source, 4096 frames/packet
///
/// This runs `/usr/bin/log` as a subprocess rather than reading `OSLogStore` in-process,
/// because `OSLogStore` cannot be used either way round — both failure modes were measured
/// on this machine:
///
/// - **Holding one store** freezes detection at launch. A store is a snapshot taken when it
///   is opened, not a live view: a handle reopened 12s later saw 13s of entries the held one
///   never showed. Every scan after launch silently found nothing, forever.
/// - **Reopening a store per scan** leaks a `com.apple.loggingsupport.stream` dispatch queue
///   and thread on every open, which are never reclaimed. Opening one every few seconds took
///   the app to 70 threads and 218 MB, at which point scans stopped completing at all and the
///   UI locked up.
///
/// A subprocess has neither problem: the kernel reclaims everything when it exits, and a
/// stream is live by definition. It is also push-based, so a format change is seen the moment
/// Music logs it instead of being polled for. The predicate is narrowed all the way down to
/// the decoder lines themselves, so this wakes up a handful of times per track rather than
/// tens of times a second.
final class AppleMusicFormatStream {
    /// Called on the main queue each time Music reports a decoded format.
    var onFormat: ((DetectedFormat) -> Void)?

    /// `log` takes an NSPredicate string. Narrowing to the decoder's own messages keeps this
    /// at ~10 lines a minute of playback instead of ~2,700.
    private static let predicate = "(subsystem == \"com.apple.coreaudio\")"
        + " AND (process == \"Music\")"
        + " AND (eventMessage CONTAINS \"ACAppleLosslessDecoder\")"

    /// How far back the launch backfill looks. Music logs a decoder line only when it
    /// *creates* a decoder and then reuses it for every following track in the same format,
    /// so the line describing what's playing right now can be many minutes old.
    private static let backfillWindow = "30m"

    private var process: Process?
    private var buffer = Data()
    private let bufferLock = NSLock()

    /// Set once a live line has arrived, so the slower backfill can never overwrite something
    /// newer that landed while it was still running. Main queue only.
    private var hasEmittedLive = false
    private var isStopped = false

    func start() {
        guard process == nil else { return }
        isStopped = false
        reapOrphanedStreams()
        spawnStream()
        backfill()
    }

    /// Re-reads recent history on demand. Needed because a *reused* decoder logs nothing:
    /// when playback resumes on a track whose format we don't know, there is no future line
    /// to wait for, only a past one to go find.
    func reseed() {
        backfill(force: true)
    }

    /// `log stream` only notices that we're gone when it next tries to write, and with a
    /// predicate this narrow that can be many minutes away — so a previous instance killed
    /// with SIGKILL (which no handler can catch) leaves one idling forever. Since our command
    /// line is unique, clear any strays before starting, which keeps the invariant "at most
    /// one of these per user" true no matter how the last run ended.
    private func reapOrphanedStreams() {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-f", "log stream --predicate \(Self.predicate)"]
        pkill.standardOutput = FileHandle.nullDevice
        pkill.standardError = FileHandle.nullDevice
        try? pkill.run()
        pkill.waitUntilExit()
    }

    func stop() {
        isStopped = true
        if let process {
            process.terminationHandler = nil
            (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            process.terminate()
        }
        process = nil
    }

    // MARK: - Live stream

    private func spawnStream() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--predicate", Self.predicate, "--style", "compact"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.ingest(data)
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.handleStreamTermination() }
        }

        do {
            try process.run()
        } catch {
            return
        }
        self.process = process
    }

    /// `log stream` should outlive the app, but if it does die the app would go quiet forever.
    /// Respawn on a delay so a process that fails immediately can't spin.
    private func handleStreamTermination() {
        process = nil
        guard !isStopped else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !self.isStopped, self.process == nil else { return }
            self.spawnStream()
        }
    }

    /// Called on the pipe's own queue. Splits whole lines out of a byte stream that can break
    /// mid-line, or mid-UTF-8-sequence, at any chunk boundary.
    private func ingest(_ data: Data) {
        var lines: [String] = []

        bufferLock.lock()
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line)
            }
        }
        // A stream that somehow never emits a newline must not grow without bound.
        if buffer.count > 1 << 20 { buffer.removeAll() }
        bufferLock.unlock()

        for line in lines {
            guard let format = Self.parse(line, date: Date()) else { continue }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.hasEmittedLive = true
                self.onFormat?(format)
            }
        }
    }

    // MARK: - Launch backfill

    /// A stream only carries the future, so at launch it says nothing about a track that
    /// started before the app did. One `log show` fills that in.
    ///
    /// `force` is for an explicit re-seed, where the caller has established that nothing is
    /// known; otherwise a result is dropped if a live line has already reported something,
    /// since this is the slower of the two paths and must never overwrite fresher data.
    private func backfill(force: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            process.arguments = [
                "show", "--last", Self.backfillWindow,
                "--predicate", Self.predicate, "--style", "compact"
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            guard (try? process.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let text = String(data: data, encoding: .utf8) else { return }
            // Newest wins, and the log is chronological, so take the last match.
            guard let line = text.split(separator: "\n").last(where: { $0.contains("Input format:") }),
                  let format = Self.parse(String(line), date: Date()) else { return }

            DispatchQueue.main.async {
                guard force || !self.hasEmittedLive else { return }
                self.onFormat?(format)
            }
        }
    }

    // MARK: - Parsing

    static func parse(_ message: String, date: Date) -> DetectedFormat? {
        guard message.contains("Input format:") else { return nil }
        guard let rateText = message.substring(between: "ch, ", and: " Hz")?.trimmingCharacters(in: .whitespaces),
              let sampleRate = Double(rateText) else { return nil }
        guard let bitText = message.substring(between: "from ", and: "-bit source")?.trimmingCharacters(in: .whitespaces),
              let bitDepth = Int(bitText) else { return nil }
        return DetectedFormat(sampleRate: sampleRate, bitDepth: bitDepth, date: date)
    }
}

private extension String {
    func substring(between start: String, and end: String) -> String? {
        guard let startRange = range(of: start) else { return nil }
        guard let endRange = range(of: end, range: startRange.upperBound..<endIndex) else { return nil }
        return String(self[startRange.upperBound..<endRange.lowerBound])
    }
}
