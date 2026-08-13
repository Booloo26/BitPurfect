import AppKit
import SimplyCoreAudio

/// Builds the menu bar panel from design 1a ("Minimal · one number, one verdict") of the
/// "Bit Perfect" design document, themeable across its four styles
/// (Graphite/Paper/Liquid glass/Ink).
///
/// 1a is deliberately just the number and the verdict — no signal path. The anti-pop, style
/// and quit rows are app plumbing the mockup has no reason to show, and are the only additions.
///
/// Layout follows the design's own box model — sections separated by full-bleed hairlines,
/// content inset 18pt, hover washes running edge to edge.
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let audio: AudioDeviceController
    private let engine: SwitchingEngine
    private let loginItemManager = LoginItemManager()
    private var notificationTokens: [NSObjectProtocol] = []

    private let panel = FloatingPanel()
    private var globalClickMonitor: Any?

    private let panelWidth: CGFloat = 318
    private let inset: CGFloat = 18
    private var contentWidth: CGFloat { panelWidth - inset * 2 }

    private let followSystemDefaultSentinel = "__follow_system_default__"
    private let autoRateSentinel = -1

    init(audio: AudioDeviceController, engine: SwitchingEngine) {
        self.audio = audio
        self.engine = engine
        super.init()

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)

        engine.onStateChanged = { [weak self] in
            self?.refresh()
        }

        refresh()
        observeChanges()
    }

    private func observeChanges() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .defaultOutputDeviceChanged,
            .deviceNominalSampleRateDidChange,
            .deviceListChanged
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
            notificationTokens.append(token)
        }
    }

    private func refresh() {
        updateStatusItemTitle()
        refreshPanelIfVisible()
    }

    // MARK: - Status item title

    private func updateStatusItemTitle() {
        guard let button = statusItem.button else { return }
        let label = engine.currentDisplayState()?.menubarLabel ?? "BitPurfect"
        button.attributedTitle = NSAttributedString(
            string: label,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)]
        )
    }

    // MARK: - Panel lifecycle

    @objc private func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    private func showPanel() {
        layOutPanel()
        panel.makeKeyAndOrderFront(nil)
        startGlobalClickMonitor()
    }

    /// Builds the card and anchors it under the status item, without touching window ordering.
    /// A state change arriving while the panel is open must not re-front the window or re-arm
    /// the dismiss monitor — doing that on every refresh made the panel flicker.
    private func layOutPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }

        let container = buildPanelContainer()

        let buttonFrameInScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let originX = buttonFrameInScreen.midX - container.frame.width / 2
        let originY = buttonFrameInScreen.minY - container.frame.height - 6

        panel.setFrame(
            NSRect(x: originX, y: originY, width: container.frame.width, height: container.frame.height),
            display: false
        )
        panel.contentView = container
    }

    private func hidePanel() {
        panel.orderOut(nil)
        stopGlobalClickMonitor()
    }

    private func refreshPanelIfVisible() {
        guard panel.isVisible else { return }
        layOutPanel()
    }

    private func startGlobalClickMonitor() {
        stopGlobalClickMonitor()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }
    }

    private func stopGlobalClickMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }

    // MARK: - Card container

    /// One stacked row of the card. Dividers and clickable rows run the full width so the
    /// hairlines and hover washes reach the card's edges, exactly like the design's blocks.
    private struct PanelRow {
        let view: NSView
        let height: CGFloat
        let isFullBleed: Bool

        static func content(_ view: NSView, _ height: CGFloat) -> PanelRow {
            PanelRow(view: view, height: height, isFullBleed: false)
        }

        static func fullBleed(_ view: NSView, _ height: CGFloat) -> PanelRow {
            PanelRow(view: view, height: height, isFullBleed: true)
        }

        static func spacer(_ height: CGFloat) -> PanelRow {
            PanelRow(view: NSView(), height: height, isFullBleed: true)
        }
    }

    private func buildPanelContainer() -> NSView {
        let theme = PanelTheme.current
        let rows = buildRows(theme: theme)
        let totalHeight = rows.reduce(0) { $0 + $1.height }

        let card = FlippedView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: totalHeight))
        card.wantsLayer = true
        card.layer?.backgroundColor = theme.panelBackground.cgColor
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = theme.panelBorder.cgColor

        var cursorY: CGFloat = 0
        for row in rows {
            row.view.frame = row.isFullBleed
                ? NSRect(x: 0, y: cursorY, width: panelWidth, height: row.height)
                : NSRect(x: inset, y: cursorY, width: contentWidth, height: row.height)
            card.addSubview(row.view)
            cursorY += row.height
        }

        return wrapInGlassIfNeeded(card, theme: theme)
    }

    /// Only the "Liquid glass" theme gets real native glass (`NSGlassEffectView`, macOS 26+);
    /// the other three themes are solid per their design spec.
    private func wrapInGlassIfNeeded(_ card: NSView, theme: PanelTheme) -> NSView {
        guard theme.isTranslucent else { return card }
        guard #available(macOS 26.0, *) else { return card }

        let glass = NSGlassEffectView(frame: card.frame)
        glass.cornerRadius = 12
        glass.style = .clear
        if #available(macOS 27.0, *) {
            glass.effectIsInteractive = true
        }
        glass.contentView = card
        return glass
    }

    private func buildRows(theme: PanelTheme) -> [PanelRow] {
        guard let state = engine.currentDisplayState() else {
            let label = makeLabel("No output device found", font: .systemFont(ofSize: 12), color: theme.textMid)
            return [
                .spacer(17),
                .content(label, 16),
                .spacer(14),
                .fullBleed(makeDivider(theme), 1),
                .fullBleed(buildQuitRow(theme), 38)
            ]
        }

        let color = theme.color(for: state.status)
        var rows: [PanelRow] = []

        // Header: status verdict on the left, what's feeding it on the right.
        rows.append(.spacer(17))
        rows.append(.content(buildStatusRow(state, color: color, theme: theme), 14))

        // The one number the whole panel exists for.
        rows.append(.spacer(6))
        let rate = buildRateRow(state, theme: theme)
        rows.append(.content(rate.view, rate.height))
        rows.append(.spacer(8))
        rows.append(.content(buildSubRow(state, theme: theme), 15))

        rows.append(.spacer(16))
        rows.append(.fullBleed(makeDivider(theme), 1))
        rows.append(.spacer(12))
        let verdict = buildVerdictRow(state.verdict, theme: theme)
        rows.append(.content(verdict.view, verdict.height))
        rows.append(.spacer(12))

        rows.append(.fullBleed(makeDivider(theme), 1))
        rows.append(.fullBleed(buildOutputRow(deviceName: state.deviceName, theme: theme), 38))

        if let device = audio.targetDevice {
            rows.append(.fullBleed(makeDivider(theme), 1))
            let section = buildForceRateSection(device: device, color: color, theme: theme)
            rows.append(.content(section, section.frame.height))
        }

        // Anti-pop sits between the rate controls and the switches, and only appears with
        // something connected that has an output stage to power down.
        if let antiPop = state.antiPop {
            rows.append(.fullBleed(makeDivider(theme), 1))
            let row = buildAntiPopRow(antiPop, theme: theme)
            rows.append(.fullBleed(row.view, row.height))
        }

        // Switches read as "on" in the design's lock green whatever the current status is —
        // they describe a setting, not the state of the stream.
        rows.append(.fullBleed(makeDivider(theme), 1))
        rows.append(.fullBleed(
            buildToggleRow(
                title: "Follow the source rate",
                isOn: state.autoOn,
                color: theme.lockedColor,
                theme: theme,
                action: #selector(toggleAutoSwitch)
            ),
            40
        ))

        rows.append(.fullBleed(makeDivider(theme), 1))
        rows.append(.fullBleed(buildLoginItemRow(isOn: loginItemManager.isEnabled, color: theme.lockedColor, theme: theme), 38))

        rows.append(.fullBleed(makeDivider(theme), 1))
        rows.append(.fullBleed(buildStyleRow(theme: theme), 38))

        rows.append(.fullBleed(makeDivider(theme), 1))
        rows.append(.fullBleed(buildQuitRow(theme), 38))

        return rows
    }

    // MARK: - Text helpers

    /// The design leans on letter-spaced monospaced caps for its labels; `tracking` is the
    /// CSS `em` value already multiplied out to points.
    private func makeLabel(
        _ text: String,
        font: NSFont,
        color: NSColor,
        tracking: CGFloat = 0,
        alignment: NSTextAlignment = .left
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.alignment = alignment
        field.lineBreakMode = .byTruncatingTail

        if tracking != 0 {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineBreakMode = .byTruncatingTail
            field.attributedStringValue = NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: color,
                .kern: tracking,
                .paragraphStyle: paragraph
            ])
        }
        return field
    }

    private func makeDivider(_ theme: PanelTheme) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = theme.divider.cgColor
        return view
    }

    private func makeDot(diameter: CGFloat, color: NSColor, x: CGFloat, y: CGFloat) -> NSView {
        let dot = NSView(frame: NSRect(x: x, y: y, width: diameter, height: diameter))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = color.cgColor
        dot.layer?.cornerRadius = diameter / 2
        return dot
    }

    // MARK: - Header

    private func buildStatusRow(_ state: PanelDisplayState, color: NSColor, theme: PanelTheme) -> NSView {
        let row = FlippedView(frame: .zero)

        row.addSubview(makeDot(diameter: 7, color: color, x: 0, y: 4))

        let word = makeLabel(
            state.status.word.uppercased(),
            font: .monospacedSystemFont(ofSize: 10, weight: .semibold),
            color: color,
            tracking: 1.2
        )
        word.sizeToFit()
        word.frame = NSRect(x: 14, y: 1, width: word.frame.width, height: 13)
        row.addSubview(word)

        // Source indicator, pushed to the right edge like the design's `margin-left:auto`.
        // It takes its natural width, giving way only if the status word leaves too little.
        let sourceText = state.isSourcePlaying ? "APPLE MUSIC" : "APPLE MUSIC · IDLE"
        let source = makeLabel(
            sourceText,
            font: .monospacedSystemFont(ofSize: 9.5, weight: .medium),
            color: theme.textLow,
            tracking: 0.76,
            alignment: .right
        )
        source.sizeToFit()
        let available = contentWidth - word.frame.maxX - 21
        let sourceWidth = min(source.frame.width, available)
        source.frame = NSRect(x: contentWidth - sourceWidth, y: 2, width: sourceWidth, height: 12)
        row.addSubview(source)

        let dotColor = state.isSourcePlaying ? theme.lockedColor : theme.hairline
        row.addSubview(makeDot(diameter: 4, color: dotColor, x: contentWidth - sourceWidth - 9, y: 5))

        return row
    }

    private func buildRateRow(_ state: PanelDisplayState, theme: PanelTheme) -> (view: NSView, height: CGFloat) {
        let row = FlippedView(frame: .zero)

        let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 56, weight: .medium)
        // The design's -.035em tracking, in points, pulls the big numerals together.
        let number = makeLabel(state.outRateStr, font: numberFont, color: theme.textHi, tracking: -1.96)
        number.sizeToFit()
        number.frame = NSRect(x: 0, y: 0, width: number.frame.width, height: number.frame.height)
        row.addSubview(number)

        let unit = makeLabel("kHz", font: .monospacedSystemFont(ofSize: 15, weight: .regular), color: theme.textLow)
        unit.sizeToFit()
        // Sit "kHz" on the same baseline as the numerals, 7pt to their right.
        let baselineY = number.firstBaselineOffsetFromTop - unit.firstBaselineOffsetFromTop
        unit.frame = NSRect(
            x: number.frame.maxX + 7,
            y: baselineY,
            width: unit.frame.width,
            height: unit.frame.height
        )
        row.addSubview(unit)

        return (row, number.frame.height)
    }

    private func buildSubRow(_ state: PanelDisplayState, theme: PanelTheme) -> NSView {
        let text = state.outBits > 0 ? "\(state.outBits)-bit · \(state.format)" : state.format
        return makeLabel(text, font: .monospacedSystemFont(ofSize: 12, weight: .regular), color: theme.textMid)
    }

    private func buildVerdictRow(_ text: String, theme: PanelTheme) -> (view: NSView, height: CGFloat) {
        let font = NSFont.systemFont(ofSize: 12.5)
        let paragraph = NSMutableParagraphStyle()
        // CSS line-height 1.45 on a 12.5pt face, minus what AppKit already leads.
        paragraph.lineSpacing = 3

        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: theme.textMid,
            .paragraphStyle: paragraph
        ])

        let label = NSTextField(wrappingLabelWithString: text)
        label.attributedStringValue = attributed
        label.isSelectable = false

        let bounding = attributed.boundingRect(
            with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        )
        return (label, ceil(bounding.height) + 2)
    }

    // MARK: - Rows

    private func makeClickableRow(theme: PanelTheme, action: Selector) -> ClickableRow {
        let row = ClickableRow(frame: .zero)
        row.target = self
        row.action = action
        row.hoverColor = theme.hoverWash
        return row
    }

    private func buildOutputRow(deviceName: String, theme: PanelTheme) -> NSView {
        let row = makeClickableRow(theme: theme, action: #selector(showDeviceMenu(_:)))

        let label = makeLabel("Output", font: .systemFont(ofSize: 12), color: theme.textLow)
        label.frame = NSRect(x: inset, y: 11, width: 80, height: 16)

        let chevronWidth: CGFloat = 14
        let valueWidth: CGFloat = 170
        let value = makeLabel(deviceName, font: .systemFont(ofSize: 12, weight: .medium), color: theme.textHi, alignment: .right)
        value.frame = NSRect(x: panelWidth - inset - chevronWidth - valueWidth - 2, y: 11, width: valueWidth, height: 16)

        let chevron = makeLabel("⌄", font: .systemFont(ofSize: 12), color: theme.textLow)
        chevron.frame = NSRect(x: panelWidth - inset - chevronWidth, y: 9, width: chevronWidth, height: 16)

        row.addSubview(label)
        row.addSubview(value)
        row.addSubview(chevron)
        return row
    }

    private func buildForceRateSection(device: AudioDevice, color: NSColor, theme: PanelTheme) -> NSView {
        let topPadding: CGFloat = 12
        let labelHeight: CGFloat = 12
        let labelGap: CGFloat = 8
        let chipHeight: CGFloat = 24
        let chipSpacing: CGFloat = 6
        let lineSpacing: CGFloat = 6
        let bottomPadding: CGFloat = 12

        let forced = audio.forcedRate
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        var chips: [(title: String, tag: Int, isOn: Bool)] = [("Auto", autoRateSentinel, forced == nil)]
        for rate in audio.availableSampleRates(of: device) {
            let isOn = forced.map { abs($0 - rate) < 0.5 } ?? false
            chips.append((PanelDisplayState.fmt(rate), Int(rate), isOn))
        }

        let section = FlippedView(frame: .zero)

        let sectionLabel = makeLabel(
            "FORCE OUTPUT RATE",
            font: .monospacedSystemFont(ofSize: 9.5, weight: .semibold),
            color: theme.textLow,
            tracking: 1.33
        )
        sectionLabel.frame = NSRect(x: 0, y: topPadding, width: contentWidth, height: labelHeight)
        section.addSubview(sectionLabel)

        var x: CGFloat = 0
        var y: CGFloat = topPadding + labelHeight + labelGap
        for chip in chips {
            let width = ceil((chip.title as NSString).size(withAttributes: [.font: font]).width) + 16
            if x > 0, x + width > contentWidth {
                x = 0
                y += chipHeight + lineSpacing
            }
            let button = makeForceRateChip(title: chip.title, tag: chip.tag, isOn: chip.isOn, activeColor: color, theme: theme, font: font)
            button.frame = NSRect(x: x, y: y, width: width, height: chipHeight)
            section.addSubview(button)
            x += width + chipSpacing
        }

        section.frame = NSRect(x: 0, y: 0, width: contentWidth, height: y + chipHeight + bottomPadding)
        return section
    }

    private func makeForceRateChip(title: String, tag: Int, isOn: Bool, activeColor: NSColor, theme: PanelTheme, font: NSFont) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(pickForcedRate(_:)))
        button.tag = tag
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.borderWidth = 1
        button.layer?.backgroundColor = (isOn ? activeColor : theme.chipBackground).cgColor
        button.layer?.borderColor = (isOn ? activeColor : theme.hairline).cgColor
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: isOn ? theme.checkTextColor : theme.textSoft
        ])
        return button
    }

    private func buildToggleRow(title: String, isOn: Bool, color: NSColor, theme: PanelTheme, action: Selector) -> NSView {
        let row = makeClickableRow(theme: theme, action: action)

        let label = makeLabel(title, font: .systemFont(ofSize: 12), color: theme.textSoft)
        label.frame = NSRect(x: inset, y: 12, width: contentWidth - 42, height: 16)

        let toggle = TogglePill(frame: NSRect(x: panelWidth - inset - 30, y: 11, width: 30, height: 18))
        toggle.isOn = isOn
        toggle.onColor = color
        toggle.offColor = theme.offTrack

        row.addSubview(label)
        row.addSubview(toggle)
        return row
    }

    /// The design's anti-pop row: a title that carries a live "Holding DAC awake" badge, a
    /// hint line underneath that says what the setting is actually doing right now, and the
    /// same pill toggle as the other switches. Height follows the wrapped hint.
    private func buildAntiPopRow(_ antiPop: PanelDisplayState.AntiPop, theme: PanelTheme) -> (view: NSView, height: CGFloat) {
        let verticalPadding: CGFloat = 11
        let titleHeight: CGFloat = 16
        let titleToHint: CGFloat = 3
        let textWidth = contentWidth - 42

        let row = makeClickableRow(theme: theme, action: #selector(toggleKeepAwake))

        let title = makeLabel("Anti-pop", font: .systemFont(ofSize: 12), color: theme.textSoft)
        title.sizeToFit()
        title.frame = NSRect(x: inset, y: verticalPadding, width: title.frame.width, height: titleHeight)
        row.addSubview(title)

        if antiPop.isHolding {
            let badge = makeHoldingBadge(theme: theme)
            badge.frame.origin = NSPoint(x: title.frame.maxX + 6, y: verticalPadding + 1)
            row.addSubview(badge)
        }

        let hintFont = NSFont.systemFont(ofSize: 10.5)
        let hintParagraph = NSMutableParagraphStyle()
        hintParagraph.lineSpacing = 1.5
        let hint = NSAttributedString(string: antiPop.hint, attributes: [
            .font: hintFont,
            .foregroundColor: theme.textLow,
            .paragraphStyle: hintParagraph
        ])
        let hintHeight = ceil(hint.boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        ).height) + 2

        let hintLabel = NSTextField(wrappingLabelWithString: antiPop.hint)
        hintLabel.attributedStringValue = hint
        hintLabel.isSelectable = false
        hintLabel.frame = NSRect(
            x: inset,
            y: verticalPadding + titleHeight + titleToHint,
            width: textWidth,
            height: hintHeight
        )
        row.addSubview(hintLabel)

        let height = verticalPadding * 2 + titleHeight + titleToHint + hintHeight
        let toggle = TogglePill(frame: NSRect(x: panelWidth - inset - 30, y: (height - 18) / 2, width: 30, height: 18))
        toggle.isOn = antiPop.isEnabled
        toggle.onColor = theme.lockedColor
        toggle.offColor = theme.offTrack
        row.addSubview(toggle)

        return (row, height)
    }

    private func makeHoldingBadge(theme: PanelTheme) -> NSView {
        let color = theme.lockedColor
        let font = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .semibold)
        let text = "HOLDING DAC AWAKE"

        let label = makeLabel(text, font: font, color: color, tracking: 0.85)
        label.sizeToFit()

        let horizontalPadding: CGFloat = 5
        let dotDiameter: CGFloat = 4
        let dotGap: CGFloat = 4
        let badgeHeight: CGFloat = 15
        let width = horizontalPadding * 2 + dotDiameter + dotGap + label.frame.width

        let badge = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: badgeHeight))
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4
        badge.layer?.backgroundColor = color.withAlphaComponent(0.16).cgColor

        let dot = makeDot(
            diameter: dotDiameter,
            color: color,
            x: horizontalPadding,
            y: (badgeHeight - dotDiameter) / 2
        )
        // The design's `bpPulse`: a slow breathe between 35% and full, so the badge reads as
        // something that's happening rather than something that happened.
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.35
        pulse.toValue = 1.0
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.layer?.add(pulse, forKey: "pulse")
        badge.addSubview(dot)

        label.frame = NSRect(
            x: horizontalPadding + dotDiameter + dotGap,
            y: (badgeHeight - label.frame.height) / 2,
            width: label.frame.width,
            height: label.frame.height
        )
        badge.addSubview(label)

        return badge
    }

    private func buildLoginItemRow(isOn: Bool, color: NSColor, theme: PanelTheme) -> NSView {
        let row = makeClickableRow(theme: theme, action: #selector(toggleLoginItem))

        let checkboxSize: CGFloat = 15
        let checkbox = NSView(frame: NSRect(x: inset, y: 11, width: checkboxSize, height: checkboxSize))
        checkbox.wantsLayer = true
        checkbox.layer?.cornerRadius = 4
        checkbox.layer?.borderWidth = 1
        checkbox.layer?.borderColor = (isOn ? color : theme.hairline).cgColor
        checkbox.layer?.backgroundColor = (isOn ? color : NSColor.clear).cgColor

        let check = makeLabel("✓", font: .systemFont(ofSize: 9, weight: .bold), color: isOn ? theme.checkTextColor : .clear, alignment: .center)
        check.frame = NSRect(x: 0, y: 1, width: checkboxSize, height: 13)
        checkbox.addSubview(check)

        let label = makeLabel("Launch at startup", font: .systemFont(ofSize: 12), color: theme.textSoft)
        label.frame = NSRect(x: inset + checkboxSize + 9, y: 11, width: contentWidth - checkboxSize - 9, height: 16)

        row.addSubview(checkbox)
        row.addSubview(label)
        return row
    }

    private func buildStyleRow(theme: PanelTheme) -> NSView {
        let row = makeClickableRow(theme: theme, action: #selector(cycleTheme))

        let label = makeLabel("Style", font: .systemFont(ofSize: 12), color: theme.textLow)
        label.frame = NSRect(x: inset, y: 11, width: 80, height: 16)

        let chevronWidth: CGFloat = 14
        let value = makeLabel(theme.name, font: .systemFont(ofSize: 12, weight: .medium), color: theme.textHi, alignment: .right)
        value.frame = NSRect(x: panelWidth - inset - chevronWidth - 152, y: 11, width: 150, height: 16)

        let chevron = makeLabel("⌄", font: .systemFont(ofSize: 12), color: theme.textLow)
        chevron.frame = NSRect(x: panelWidth - inset - chevronWidth, y: 9, width: chevronWidth, height: 16)

        row.addSubview(label)
        row.addSubview(value)
        row.addSubview(chevron)
        return row
    }

    private func buildQuitRow(_ theme: PanelTheme) -> NSView {
        let row = makeClickableRow(theme: theme, action: #selector(quit))
        let label = makeLabel("Quit BitPurfect", font: .systemFont(ofSize: 11.5), color: theme.textLow)
        label.frame = NSRect(x: inset, y: 11, width: contentWidth, height: 16)
        row.addSubview(label)
        return row
    }

    // MARK: - Actions

    @objc private func showDeviceMenu(_ sender: ClickableRow) {
        let menu = NSMenu()
        let currentUID = audio.preferredDeviceUID

        let followItem = NSMenuItem(title: "Follow System Default", action: #selector(selectDeviceFromMenu(_:)), keyEquivalent: "")
        followItem.target = self
        followItem.representedObject = followSystemDefaultSentinel
        followItem.state = currentUID == nil ? .on : .off
        menu.addItem(followItem)
        menu.addItem(.separator())

        for device in audio.outputDevices {
            guard let uid = device.uid else { continue }
            let item = NSMenuItem(title: device.name, action: #selector(selectDeviceFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = uid
            item.state = uid == currentUID ? .on : .off
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: inset, y: sender.bounds.height), in: sender)
    }

    @objc private func selectDeviceFromMenu(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        audio.preferredDeviceUID = (value == followSystemDefaultSentinel) ? nil : value
        engine.reapplyToCurrentDevice()
        refresh()
    }

    @objc private func pickForcedRate(_ sender: NSButton) {
        audio.forcedRate = sender.tag == autoRateSentinel ? nil : Double(sender.tag)
        engine.reapplyToCurrentDevice()
        refresh()
    }

    /// Matches the design: with a rate pinned, this row hands control back to the source
    /// rather than toggling auto-switch off underneath the override.
    @objc private func toggleAutoSwitch() {
        if audio.forcedRate != nil {
            audio.forcedRate = nil
            engine.isEnabled = true
            engine.reapplyToCurrentDevice()
        } else {
            engine.isEnabled.toggle()
        }
        refresh()
    }

    @objc private func toggleKeepAwake() {
        engine.isKeepAwakeEnabled.toggle()
        refresh()
    }

    @objc private func toggleLoginItem() {
        let newValue = !loginItemManager.isEnabled
        if loginItemManager.setEnabled(newValue), newValue {
            loginItemManager.openSystemSettingsIfNeeded()
        }
        refresh()
    }

    @objc private func cycleTheme() {
        _ = PanelTheme.advance()
        refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    deinit {
        let center = NotificationCenter.default
        notificationTokens.forEach { center.removeObserver($0) }
        stopGlobalClickMonitor()
    }
}
