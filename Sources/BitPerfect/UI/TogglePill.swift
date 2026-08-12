import AppKit

/// A hand-drawn pill toggle matching the design exactly (system NSSwitch looks nothing
/// like it). Purely decorative — `hitTest` returns nil so clicks pass through to whatever
/// row it's sitting in, which owns the actual click handling.
final class TogglePill: NSView {
    var isOn: Bool = false {
        didSet { needsDisplay = true }
    }

    var onColor: NSColor = PanelColors.locked {
        didSet { needsDisplay = true }
    }

    var offColor: NSColor = NSColor.white.withAlphaComponent(0.18) {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let pillPath = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        (isOn ? onColor : offColor).setFill()
        pillPath.fill()

        let knobDiameter = bounds.height - 4
        let knobX = isOn ? bounds.width - knobDiameter - 2 : 2
        let knobRect = NSRect(x: knobX, y: 2, width: knobDiameter, height: knobDiameter)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knobRect).fill()
    }
}
