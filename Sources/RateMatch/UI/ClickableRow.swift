import AppKit

/// A full-row click target with a subtle hover highlight, matching the design's
/// `cursor:pointer` + `style-hover` rows (Output, Auto-switch). Claims every point in its
/// bounds so clicks landing on a decorative child label still register as a row click.
final class ClickableRow: FlippedView {
    weak var target: NSObject?
    var action: Selector?
    var hoverColor: NSColor = NSColor.white.withAlphaComponent(0.045)

    private var trackingArea: NSTrackingArea?
    private let highlightLayer = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        highlightLayer.backgroundColor = NSColor.clear.cgColor
        layer?.insertSublayer(highlightLayer, at: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        return bounds.contains(localPoint) ? self : nil
    }

    override func layout() {
        super.layout()
        highlightLayer.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        highlightLayer.backgroundColor = hoverColor.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        highlightLayer.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        if let action {
            _ = target?.perform(action, with: self)
        }
    }
}
