import AppKit

final class ComponentTextField: NSTextField {
    var onInteraction: (() -> Void)?
    var isLinkedHighlighted = false {
        didSet {
            wantsLayer = true
            layer?.borderWidth = isLinkedHighlighted ? 2 : 0
            layer?.borderColor = NSColor.systemOrange.cgColor
            layer?.cornerRadius = 2
        }
    }

    override func mouseDown(with event: NSEvent) {
        onInteraction?()
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onInteraction?() }
        return accepted
    }
}
