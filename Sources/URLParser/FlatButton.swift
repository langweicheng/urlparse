import AppKit

/// Native button tracking and actions, with lightweight hover/press feedback.
final class FlatButton: NSButton {
    private var hoverArea: NSTrackingArea?
    private var hovered = false

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 20 // 10 pt breathing room on each side of the native content.
        return size
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isEnabled, isHighlighted || hovered {
            NSColor.controlAccentColor.withAlphaComponent(isHighlighted ? 0.26 : 0.10).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        super.draw(dirtyRect)
    }
}

final class PaddedButtonCell: NSButtonCell {
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: cellFrame.insetBy(dx: 10, dy: 0), in: controlView)
    }
}
