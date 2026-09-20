import Foundation

/// One contiguous replacement. Undo retains only changed text, not two documents.
public struct TextPatch {
    public let location: Int
    public let removed: String
    public let inserted: String

    public init(from old: String, to new: String) {
        let a = old as NSString, b = new as NSString
        var prefix = 0
        while prefix < min(a.length, b.length), a.character(at: prefix) == b.character(at: prefix) { prefix += 1 }
        // Keep UTF-16 surrogate pairs intact at the replacement boundaries.
        if prefix > 0, prefix < a.length, (0xDC00...0xDFFF).contains(a.character(at: prefix)) { prefix -= 1 }
        var suffix = 0
        while suffix < min(a.length, b.length) - prefix,
              a.character(at: a.length - suffix - 1) == b.character(at: b.length - suffix - 1) { suffix += 1 }
        if suffix > 0, (0xDC00...0xDFFF).contains(a.character(at: a.length - suffix)) { suffix -= 1 }
        location = prefix
        removed = a.substring(with: NSRange(location: prefix, length: a.length - prefix - suffix))
        inserted = b.substring(with: NSRange(location: prefix, length: b.length - prefix - suffix))
    }

    public func apply(to text: String, reversed: Bool = false) -> String {
        let source = reversed ? inserted : removed
        let replacement = reversed ? removed : inserted
        return (text as NSString).replacingCharacters(in: NSRange(location: location, length: (source as NSString).length), with: replacement)
    }
}
