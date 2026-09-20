import AppKit
import URLCore

final class JSONTextView: NSTextView {
    private var index = JSONIndex("")
    private var highlighted: NSRange?
    private var menuTarget: (field: JSONIndex.Field, key: Bool)?
    private static func color(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    convenience init() {
        let storage = NSTextStorage(), layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
    }

    func refreshSyntax() {
        index = JSONIndex(string)
        highlighted = nil
        let all = NSRange(location: 0, length: (string as NSString).length)
        guard let layoutManager else { return }
        backgroundColor = .white; textColor = .black; insertionPointColor = .black
        selectedTextAttributes = [.backgroundColor: Self.color(0x5974AB), .foregroundColor: NSColor.white]
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: all)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
        for token in index.tokens {
            let color: NSColor
            switch token.kind {
            case .key: color = Self.color(0x660E7A)
            case .string: color = Self.color(0x008000)
            case .number: color = Self.color(0x0000FF)
            case .literal: color = Self.color(0x000080)
            case .punctuation: continue
            }
            layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: token.range)
        }
        refreshSelectionHighlight()
    }

    func refreshSelectionHighlight() {
        if let highlighted, NSMaxRange(highlighted) <= (string as NSString).length {
            layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: highlighted)
        }
        highlighted = nil
        guard let field = index.field(at: selectedRange().location), NSMaxRange(field.range) <= (string as NSString).length else { return }
        highlighted = field.range
        layoutManager?.addTemporaryAttribute(.backgroundColor, value: Self.color(0xFFFAE3), forCharacterRange: field.range)
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
