import AppKit

/// Design tokens from the "Bit Perfect" design (oklch(0.76 0.15 152) / oklch(0.78 0.15 74),
/// converted to sRGB) — green for a bit-perfect lock, amber for a resampled passthrough.
enum PanelColors {
    static let locked = NSColor(srgbRed: 91.0 / 255, green: 204.0 / 255, blue: 128.0 / 255, alpha: 1)
    static let resampled = NSColor(srgbRed: 240.0 / 255, green: 167.0 / 255, blue: 50.0 / 255, alpha: 1)

    /// The design dims status colors 62% toward near-black for light themes
    /// (`color-mix(in oklch, c 62%, #101014)`); approximated here in sRGB.
    static let lockedDimmed = NSColor(srgbRed: 63.0 / 255, green: 133.0 / 255, blue: 87.0 / 255, alpha: 1)
    static let resampledDimmed = NSColor(srgbRed: 155.0 / 255, green: 110.0 / 255, blue: 39.0 / 255, alpha: 1)
}

/// The design's three status readings. The color each one paints with is theme-dependent,
/// so it lives on `PanelTheme` rather than here.
enum PanelStatus {
    case locked
    case resampled
    case idle

    var word: String {
        switch self {
        case .locked: return "Bit perfect"
        case .resampled: return "Resampled"
        case .idle: return "Idle · default"
        }
    }
}

/// Everything the panel needs to render for one moment in time — mirrors the design's
/// `renderVals()` so the UI layer stays a pure function of this state.
struct PanelDisplayState {
    let status: PanelStatus
    let menubarLabel: String

    let outRateStr: String
    let outBits: Int
    let format: String

    let verdict: String

    let deviceName: String
    let autoOn: Bool

    /// Drives the design's source indicator in the panel header.
    let isSourcePlaying: Bool

    /// nil unless something with a poppable output stage is connected — the design gates
    /// this whole row on `dacConnected`, so on the internal speakers it doesn't appear.
    let antiPop: AntiPop?

    struct AntiPop {
        /// The setting, which is what the toggle reflects.
        let isEnabled: Bool
        /// Whether the silent stream is actually running right now, which is what the
        /// "Holding DAC awake" badge reflects.
        let isHolding: Bool
        let hint: String
    }

    static func fmt(_ rate: Double) -> String {
        String(format: "%.1f", rate / 1000)
    }
}
