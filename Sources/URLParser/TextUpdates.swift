import AppKit
import URLCore

extension NSTextView {
    /// Keep unchanged text, layout, and temporary syntax attributes in place.
    func replaceContent(with text: String) {
        guard string != text else { return }
        let patch = TextPatch(from: string, to: text)
        let range = NSRange(location: patch.location, length: (patch.removed as NSString).length)
        textStorage?.replaceCharacters(in: range, with: patch.inserted)
    }
}
