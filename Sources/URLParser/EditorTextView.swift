import AppKit

class EditorTextView: NSTextView {
    var onInteraction: (() -> Void)?
    private(set) var interactionPosition: Int?
    private(set) var linkedHighlightRanges: [NSRange] = []
    static let linkedHighlightColor = NSColor.systemYellow.withAlphaComponent(0.4)

    func highlightLinkedRanges(_ ranges: [NSRange], scroll: Bool = false) {
        let length = (string as NSString).length
        for range in linkedHighlightRanges where range.location < length {
            let clipped = NSIntersectionRange(range, NSRange(location: 0, length: length))
            layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: clipped)
        }
        linkedHighlightRanges = ranges.filter { $0.location != NSNotFound && $0.length > 0 && NSMaxRange($0) <= length }
        for range in linkedHighlightRanges {
            layoutManager?.addTemporaryAttribute(.backgroundColor, value: Self.linkedHighlightColor, forCharacterRange: range)
        }
        if scroll, let range = linkedHighlightRanges.first { scrollRangeToVisible(range) }
    }

    func didInteract(at position: Int? = nil) {
        interactionPosition = position
        defer { interactionPosition = nil }
        onInteraction?()
    }

    func clickedCharacterIndex(for event: NSEvent) -> Int {
        guard !string.isEmpty, let layoutManager, let textContainer else { return NSNotFound }
        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs,
              layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).contains(containerPoint) else { return NSNotFound }
        return layoutManager.characterIndexForGlyph(at: glyph)
    }

    override func mouseDown(with event: NSEvent) {
        let position = clickedCharacterIndex(for: event)
        super.mouseDown(with: event)
        didInteract(at: selectedRange().length == 0 ? position : nil)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.allowsContextMenuPlugIns = false
        for (title, action) in [("剪切", #selector(cut(_:))), ("复制", #selector(copy(_:))), ("粘贴", #selector(paste(_:))), ("全选", #selector(selectAll(_:)))] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
        }
        return menu
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menu(for: event) else { return }
        menu.allowsContextMenuPlugIns = false
        // Use a regular popup to avoid AppKit appending contextual AutoFill/Services.
        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }
}
