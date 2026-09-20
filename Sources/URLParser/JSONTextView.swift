import AppKit
import URLCore

final class JSONTextView: NSTextView, NSTextStorageDelegate {
    private var previousLength = 0
    private var needsFullHighlight = true
    private var editedStart: Int?
    private var editedEnd = 0
    private var index = JSONIndex("")
    private var highlighted: NSRange?
    private var menuTarget: (field: JSONIndex.Field, key: Bool)?
    private static func color(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    private static let keyColor = color(0x660E7A)
    private static let stringColor = color(0x008000)
    private static let numberColor = color(0x0000FF)
    private static let literalColor = color(0x000080)
    private static let pairColor = color(0xFFFAE3)

    convenience init() {
        let storage = NSTextStorage(), layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = true
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
        storage.delegate = self
        backgroundColor = .white; textColor = .black; insertionPointColor = .black
        selectedTextAttributes = [.backgroundColor: Self.color(0x5974AB), .foregroundColor: NSColor.white]
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        if editedStart != nil || (editedRange.location == 0 && editedRange.length == textStorage.length) {
            needsFullHighlight = true
        }
        editedStart = min(editedStart ?? editedRange.location, editedRange.location)
        editedEnd = NSMaxRange(editedRange)
    }

    func refreshSyntax() {
        let next = JSONIndex(string)
        let length = (string as NSString).length
        guard let layoutManager else { return }
        let all = NSRange(location: 0, length: length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
        highlighted = nil
        var first = 0
        var end = next.tokens.count
        if !needsFullHighlight {
            while first < min(index.tokens.count, next.tokens.count),
                  NSMaxRange(next.tokens[first].range) <= (editedStart ?? 0),
                  index.tokens[first].kind == next.tokens[first].kind,
                  index.tokens[first].range == next.tokens[first].range { first += 1 }
            var oldEnd = index.tokens.count
            let delta = length - previousLength
            while end > first, oldEnd > first {
                let old = index.tokens[oldEnd - 1], new = next.tokens[end - 1]
                guard new.range.location >= editedEnd,
                      old.kind == new.kind, old.range.length == new.range.length,
                      old.range.location + delta == new.range.location else { break }
                oldEnd -= 1; end -= 1
            }
        }
        // Include neighboring tokens: insertions at their boundaries may inherit
        // a color from the preceding token through TextKit.
        let startToken = max(0, first - 1)
        let endToken = min(next.tokens.count, end + 1)
        let start = startToken < next.tokens.count ? next.tokens[startToken].range.location : 0
        let finish = endToken > 0 ? NSMaxRange(next.tokens[endToken - 1].range) : length
        let dirty = NSRange(location: start, length: max(0, finish - start))
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: dirty)
        for token in next.tokens[startToken..<endToken] {
            let color: NSColor
            switch token.kind {
            case .key: color = Self.keyColor
            case .string: color = Self.stringColor
            case .number: color = Self.numberColor
            case .literal: color = Self.literalColor
            case .punctuation: continue
            }
            layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: token.range)
        }
        index = next
        previousLength = length
        needsFullHighlight = false
        editedStart = nil; editedEnd = 0
        refreshSelectionHighlight()
    }

    func refreshSelectionHighlight() {
        if let highlighted, NSMaxRange(highlighted) <= (string as NSString).length {
            layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: highlighted)
        }
        highlighted = nil
        guard let field = index.field(at: selectedRange().location), NSMaxRange(field.range) <= (string as NSString).length else { return }
        highlighted = field.range
        layoutManager?.addTemporaryAttribute(.backgroundColor, value: Self.pairColor, forCharacterRange: field.range)
    }

    override func mouseDown(with event: NSEvent) {
        if !event.modifierFlags.contains(.shift), !event.modifierFlags.contains(.command) {
            let position = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
            if let field = index.field(at: position), NSLocationInRange(position, field.key) {
                window?.makeFirstResponder(self)
                setSelectedRange(JSONIndex.contentRange(field.key, in: string))
                refreshSelectionHighlight()
                return
            }
        }
        super.mouseDown(with: event)
        refreshSelectionHighlight()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let position = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        guard let field = index.field(at: position),
              NSLocationInRange(position, field.key) || NSLocationInRange(position, field.value) else {
            menuTarget = nil
            return super.menu(for: event)
        }
        let key = NSLocationInRange(position, field.key)
        menuTarget = (field, key)
        window?.makeFirstResponder(self)
        setSelectedRange(JSONIndex.contentRange(key ? field.key : field.value, in: string))
        refreshSelectionHighlight()
        let menu = NSMenu()
        let copy = menu.addItem(withTitle: key ? "复制 Key" : "复制 Value", action: #selector(copyToken), keyEquivalent: "")
        copy.target = self
        let delete = menu.addItem(withTitle: key ? "删除 Key（整个参数）" : "删除 Value（清空值）", action: #selector(deleteToken), keyEquivalent: "")
        delete.target = self
        return menu
    }
    @objc private func copyToken() {
        guard let target = menuTarget else { return }
        let value = JSONIndex.copiedText(target.key ? target.field.key : target.field.value, in: string)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
    }
    @objc private func deleteToken() {
        guard let target = menuTarget else { return }
        let range = target.key ? target.field.deletion : target.field.value
        let replacement = target.key ? "" : "\"\""
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        setSelectedRange(NSRange(location: min(range.location, (string as NSString).length), length: 0))
        menuTarget = nil
        didChangeText()
    }
}
