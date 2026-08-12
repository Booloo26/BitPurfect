import AppKit

/// A container with a top-left origin, so row layout can be computed top-to-bottom
/// instead of fighting AppKit's default bottom-left coordinate space.
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
