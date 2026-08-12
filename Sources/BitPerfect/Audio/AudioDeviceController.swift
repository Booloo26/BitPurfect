import Foundation
import SimplyCoreAudio

final class AudioDeviceController {
    private let core = SimplyCoreAudio()
    private let defaults = UserDefaults.standard
    private let preferredDeviceUIDKey = "preferredOutputDeviceUID"
    private let forcedRateKey = "forcedOutputRate"
    private let keepAwakeKey = "keepDACAwake"

    var outputDevices: [AudioDevice] {
        core.allOutputDevices
    }

    var defaultOutputDevice: AudioDevice? {
        core.defaultOutputDevice
    }

    /// UID of the device the user pinned Bit Perfect to, or nil to follow the system default output device.
    var preferredDeviceUID: String? {
        get { defaults.string(forKey: preferredDeviceUIDKey) }
        set { defaults.set(newValue, forKey: preferredDeviceUIDKey) }
    }

    /// The device Bit Perfect should act on: the pinned device if still connected, otherwise the system default.
    var targetDevice: AudioDevice? {
        if let uid = preferredDeviceUID, let pinned = outputDevices.first(where: { $0.uid == uid }) {
            return pinned
        }
        return defaultOutputDevice
    }

    /// A rate the user manually pinned, overriding auto-detection until cleared ("Auto").
    var forcedRate: Double? {
        get {
            let value = defaults.double(forKey: forcedRateKey)
            return value > 0 ? value : nil
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: forcedRateKey)
            } else {
                defaults.removeObject(forKey: forcedRateKey)
            }
        }
    }

    /// Whether Bit Perfect holds an outboard DAC's stream open so it can't fall asleep
    /// between tracks and pop on the way back. On by default — the pop is the thing users
    /// notice, and the silence we feed it is bit-identical to no signal at all.
    var keepAwakeEnabled: Bool {
        get { defaults.object(forKey: keepAwakeKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: keepAwakeKey) }
    }

    /// The design's `dacConnected`, narrowed to outboard DACs on a wire — the devices that
    /// actually power an output stage down and click on the way back.
    ///
    /// Deliberately excludes the Mac's own headphone jack, which the design counts as
    /// connected: headphones plugged straight into the MacBook Pro don't pop, so holding
    /// that stream open would cost power for nothing. Bluetooth and AirPlay are out for the
    /// same reason, plus the battery drain of keeping a wireless link streaming silence.
    func isAntiPopTarget(_ device: AudioDevice) -> Bool {
        switch device.transportType {
        case .usb, .fireWire, .thunderbolt, .pci, .displayPort, .hdmi, .avb:
            return true
        default:
            return false
        }
    }

    func currentSampleRate(of device: AudioDevice) -> Double? {
        device.nominalSampleRate
    }

    /// The bit depth the device actually receives, as opposed to the source's — the design
    /// shows this one whenever the output isn't a bit-perfect passthrough.
    func physicalBitDepth(of device: AudioDevice) -> Int? {
        guard let format = device.streams(scope: .output)?.first?.physicalFormat else { return nil }
        let bits = Int(format.mBitsPerChannel)
        return bits > 0 ? bits : nil
    }

    func availableSampleRates(of device: AudioDevice) -> [Double] {
        (device.nominalSampleRates ?? []).sorted()
    }

    /// The rate to actually run the device at for a given source rate.
    ///
    /// Picking the numerically closest rate is the wrong answer for an app whose whole point is
    /// clean digital audio: on a device that stops at 96 kHz, a 176.4 kHz source is *nearer* to
    /// 96 kHz than to 88.2 kHz, but 88.2 is an exact 2:1 decimation while 96 is a 1.8375:1
    /// resample with interpolation error on every sample. So the two clock families
    /// (44.1/88.2/176.4/352.8 and 48/96/192/384) are honoured first, and distance only decides
    /// between rates once the family is settled.
    ///
    /// Preference order: the source rate itself, then the highest same-family rate below it
    /// (integer decimation), then the lowest same-family rate above it (integer interpolation),
    /// and only if the device offers nothing in that family at all, the nearest rate overall.
    func bestSupportedRate(for source: Double, on device: AudioDevice) -> Double? {
        let rates = availableSampleRates(of: device)
        guard !rates.isEmpty else { return nil }

        if let exact = rates.first(where: { abs($0 - source) < 0.5 }) {
            return exact
        }

        if let base = Self.familyBase(of: source) {
            let family = rates.filter { Int($0.rounded()) % base == 0 }
            if let below = family.filter({ $0 < source }).max() { return below }
            if let above = family.filter({ $0 > source }).min() { return above }
        }

        return rates.min { abs($0 - source) < abs($1 - source) }
    }

    /// 44100 or 48000 when `rate` is an integer multiple of one of them, else nil for rates
    /// that belong to neither family (32 kHz and friends).
    private static func familyBase(of rate: Double) -> Int? {
        let hz = Int(rate.rounded())
        if hz % 44100 == 0 { return 44100 }
        if hz % 48000 == 0 { return 48000 }
        return nil
    }

    @discardableResult
    func setSampleRate(_ rate: Double, on device: AudioDevice) -> Bool {
        device.setNominalSampleRate(rate)
    }
}
