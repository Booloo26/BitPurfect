import AppKit

/// The four themes from the design's `THEMES` array. Colors are transcribed directly from
/// the design's hex/rgba values; only the two status colors (locked/resampled) are OKLCH
/// in the source and get an sRGB approximation for the light themes' `color-mix` dimming.
struct PanelTheme {
    let name: String
    let isLight: Bool
    let isTranslucent: Bool
    let panelBackground: NSColor
    let textHi: NSColor
    let textSoft: NSColor
    let textMid: NSColor
    let textLow: NSColor
    let divider: NSColor
    let panelBorder: NSColor
    let hairline: NSColor
    let chipBackground: NSColor
    let hoverWash: NSColor
    let offTrack: NSColor
    let checkTextColor: NSColor

    var lockedColor: NSColor { isLight ? PanelColors.lockedDimmed : PanelColors.locked }
    var resampledColor: NSColor { isLight ? PanelColors.resampledDimmed : PanelColors.resampled }

    static let graphite = PanelTheme(
        name: "Graphite", isLight: false, isTranslucent: false,
        panelBackground: NSColor(srgbRed: 0x17 / 255.0, green: 0x18 / 255.0, blue: 0x1a / 255.0, alpha: 1),
        textHi: NSColor(srgbRed: 244 / 255, green: 243 / 255, blue: 240 / 255, alpha: 1),
        textSoft: NSColor(srgbRed: 244 / 255, green: 243 / 255, blue: 240 / 255, alpha: 0.75),
        textMid: NSColor(srgbRed: 244 / 255, green: 243 / 255, blue: 240 / 255, alpha: 0.56),
        textLow: NSColor(srgbRed: 244 / 255, green: 243 / 255, blue: 240 / 255, alpha: 0.4),
        divider: NSColor.white.withAlphaComponent(0.07),
        panelBorder: NSColor.white.withAlphaComponent(0.1),
        hairline: NSColor.white.withAlphaComponent(0.14),
        chipBackground: NSColor.white.withAlphaComponent(0.07),
        hoverWash: NSColor.white.withAlphaComponent(0.045),
        offTrack: NSColor.white.withAlphaComponent(0.18),
        checkTextColor: NSColor(srgbRed: 0x10 / 255.0, green: 0x11 / 255.0, blue: 0x13 / 255.0, alpha: 1)
    )

    static let paper = PanelTheme(
        name: "Paper", isLight: true, isTranslucent: false,
        panelBackground: NSColor(srgbRed: 0xfb / 255.0, green: 0xfa / 255.0, blue: 0xf8 / 255.0, alpha: 1),
        textHi: NSColor(srgbRed: 0x17 / 255.0, green: 0x18 / 255.0, blue: 0x1a / 255.0, alpha: 1),
        textSoft: NSColor(srgbRed: 23 / 255, green: 24 / 255, blue: 26 / 255, alpha: 0.74),
        textMid: NSColor(srgbRed: 23 / 255, green: 24 / 255, blue: 26 / 255, alpha: 0.58),
        textLow: NSColor(srgbRed: 23 / 255, green: 24 / 255, blue: 26 / 255, alpha: 0.44),
        divider: NSColor.black.withAlphaComponent(0.08),
        panelBorder: NSColor.black.withAlphaComponent(0.12),
        hairline: NSColor.black.withAlphaComponent(0.14),
        chipBackground: NSColor.black.withAlphaComponent(0.06),
        hoverWash: NSColor.black.withAlphaComponent(0.035),
        offTrack: NSColor.black.withAlphaComponent(0.18),
        checkTextColor: NSColor(srgbRed: 0xfb / 255.0, green: 0xfa / 255.0, blue: 0xf8 / 255.0, alpha: 1)
    )

    static let liquidGlass = PanelTheme(
        name: "Liquid glass", isLight: true, isTranslucent: true,
        panelBackground: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.42),
        textHi: NSColor(srgbRed: 0x14 / 255.0, green: 0x15 / 255.0, blue: 0x19 / 255.0, alpha: 1),
        textSoft: NSColor(srgbRed: 20 / 255, green: 21 / 255, blue: 25 / 255, alpha: 0.74),
        textMid: NSColor(srgbRed: 20 / 255, green: 21 / 255, blue: 25 / 255, alpha: 0.6),
        textLow: NSColor(srgbRed: 20 / 255, green: 21 / 255, blue: 25 / 255, alpha: 0.46),
        divider: NSColor.white.withAlphaComponent(0.5),
        panelBorder: NSColor.white.withAlphaComponent(0.6),
        hairline: NSColor(srgbRed: 20 / 255, green: 21 / 255, blue: 25 / 255, alpha: 0.16),
        chipBackground: NSColor.white.withAlphaComponent(0.55),
        hoverWash: NSColor.white.withAlphaComponent(0.32),
        offTrack: NSColor(srgbRed: 20 / 255, green: 21 / 255, blue: 25 / 255, alpha: 0.22),
        checkTextColor: NSColor(srgbRed: 0xfb / 255.0, green: 0xfa / 255.0, blue: 0xf8 / 255.0, alpha: 1)
    )

    static let ink = PanelTheme(
        name: "Ink", isLight: false, isTranslucent: false,
        panelBackground: NSColor(srgbRed: 0x05 / 255.0, green: 0x10 / 255.0, blue: 0x0f / 255.0, alpha: 1),
        textHi: NSColor(srgbRed: 0xea / 255.0, green: 0xfa / 255.0, blue: 0xf4 / 255.0, alpha: 1),
        textSoft: NSColor(srgbRed: 234 / 255, green: 250 / 255, blue: 244 / 255, alpha: 0.76),
        textMid: NSColor(srgbRed: 234 / 255, green: 250 / 255, blue: 244 / 255, alpha: 0.58),
        textLow: NSColor(srgbRed: 234 / 255, green: 250 / 255, blue: 244 / 255, alpha: 0.42),
        divider: NSColor(srgbRed: 234 / 255, green: 250 / 255, blue: 244 / 255, alpha: 0.09),
        panelBorder: NSColor(srgbRed: 234 / 255, green: 250 / 255, blue: 244 / 255, alpha: 0.14),
        hairline: NSColor(srgbRed: 234 / 255, green: 250 / 255, blue: 244 / 255, alpha: 0.18),
        chipBackground: NSColor(srgbRed: 234 / 255, green: 250 / 255, blue: 244 / 255, alpha: 0.08),
        hoverWash: NSColor(srgbRed: 234 / 255, green: 250 / 255, blue: 244 / 255, alpha: 0.05),
        offTrack: NSColor(srgbRed: 234 / 255, green: 250 / 255, blue: 244 / 255, alpha: 0.2),
        checkTextColor: NSColor(srgbRed: 0x05 / 255.0, green: 0x10 / 255.0, blue: 0x0f / 255.0, alpha: 1)
    )

    /// The design paints an idle panel in the theme's mid text color rather than in either
    /// status color — nothing is locked, and nothing is wrong.
    func color(for status: PanelStatus) -> NSColor {
        switch status {
        case .locked: return lockedColor
        case .resampled: return resampledColor
        case .idle: return textMid
        }
    }

    static let all: [PanelTheme] = [.graphite, .paper, .liquidGlass, .ink]

    private static let selectedIndexKey = "selectedThemeIndex"

    static var current: PanelTheme {
        let index = UserDefaults.standard.integer(forKey: selectedIndexKey)
        return all[index % all.count]
    }

    static func advance() -> PanelTheme {
        let index = (UserDefaults.standard.integer(forKey: selectedIndexKey) + 1) % all.count
        UserDefaults.standard.set(index, forKey: selectedIndexKey)
        return all[index]
    }
}
