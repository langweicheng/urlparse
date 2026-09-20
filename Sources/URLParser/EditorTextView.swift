import AppKit

class EditorTextView: NSTextView {
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
