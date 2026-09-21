import Foundation

/// UTF-16 offsets match NSTextView, including escaped strings and emoji.
public struct JSONIndex {
    public enum Kind { case key, string, number, literal, punctuation }
    public struct Token { public var kind: Kind; public let range: NSRange }
    public struct Field {
        public let key: NSRange
        public let value: NSRange
        public let deletion: NSRange
        public var range: NSRange { NSRange(location: key.location, length: NSMaxRange(value) - key.location) }
    }
    public let tokens: [Token]
    public let fields: [Field]
    public let isValid: Bool

    public init(_ text: String) {
        let chars = Array(text.utf16)
        var tokens: [Token] = []
        var i = 0
        while i < chars.count {
            let start = i, c = chars[i]
            if [9, 10, 13, 32].contains(c) { i += 1; continue }
            if c == 34 {
                i += 1
                while i < chars.count {
                    if chars[i] == 92 { i = min(i + 2, chars.count) }
                    else if chars[i] == 34 { i += 1; break }
                    else { i += 1 }
                }
                var next = i
                while next < chars.count, [9, 10, 13, 32].contains(chars[next]) { next += 1 }
                tokens.append(Token(kind: next < chars.count && chars[next] == 58 ? .key : .string, range: NSRange(location: start, length: i - start)))
            } else if [123, 125, 91, 93, 58, 44].contains(c) {
                i += 1; tokens.append(Token(kind: .punctuation, range: NSRange(location: start, length: 1)))
            } else {
                i += 1
                while i < chars.count, ![9, 10, 13, 32, 123, 125, 91, 93, 58, 44, 34].contains(chars[i]) { i += 1 }
                tokens.append(Token(kind: c == 45 || (48...57).contains(c) ? .number : .literal, range: NSRange(location: start, length: i - start)))
            }
        }
        self.tokens = tokens
        isValid = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) is [String: Any]
        var fields: [Field] = []
        if isValid, chars.first(where: { ![9, 10, 13, 32].contains($0) }) == 123 {
            var t = 1
            var precedingComma: Int?
            while t + 2 < tokens.count, tokens[t].kind == .key {
                let key = tokens[t].range
                t += 2 // key and colon
                let start = tokens[t].range.location
                var depth = 0
                var end = start
                while t < tokens.count {
                    let token = tokens[t], c = chars[token.range.location]
                    if token.kind == .punctuation {
                        if depth == 0, c == 44 || c == 125 { break }
                        if c == 91 || c == 123 { depth += 1 }
                        if c == 93 || c == 125 { depth -= 1 }
                    }
                    end = NSMaxRange(token.range); t += 1
                }
                let hasComma = t < tokens.count && chars[tokens[t].range.location] == 44
                // Include whitespace before the field, retaining the following
                // field's indentation (or the closing brace's newline).
                let beforeField = precedingComma.map { $0 + 1 } ?? NSMaxRange(tokens[0].range)
                let deleteStart = hasComma ? beforeField : (precedingComma ?? beforeField)
                let deleteEnd = hasComma ? NSMaxRange(tokens[t].range) : end
                fields.append(Field(key: key, value: NSRange(location: start, length: end - start), deletion: NSRange(location: deleteStart, length: deleteEnd - deleteStart)))
                if hasComma { precedingComma = tokens[t].range.location; t += 1 } else { break }
            }
        }
        self.fields = fields
    }

    public func field(at index: Int) -> Field? { fields.first { NSLocationInRange(index, $0.range) } }

    /// The text must be the same snapshot used to create this index.
    public func selection(at offset: Int, in text: String) -> URLSelection? {
        guard let field = field(at: offset) else { return nil }
        let name = Self.copiedText(field.key, in: text)
        guard uniqueField(named: name, in: text) != nil else { return nil }
        if NSLocationInRange(offset, field.key) { return .queryKey(name) }
        guard NSLocationInRange(offset, field.value) else { return nil }
        if let elements = arrayElements(in: field.value, text: text) {
            let occurrence = elements.firstIndex { NSLocationInRange(offset, $0) }
            return .queryValue(name, occurrence: occurrence)
        }
        return .queryValue(name, occurrence: 0)
    }

    /// Keys and scalar values include their JSON quotes. Array selections can
    /// refer to an individual occurrence or the complete array value.
    public func range(for selection: URLSelection, in text: String) -> NSRange? {
        let name: String
        switch selection {
        case .component: return nil
        case .queryKey(let key), .queryValue(let key, _): name = key
        }
        guard let field = uniqueField(named: name, in: text) else { return nil }
        switch selection {
        case .queryKey: return field.key
        case .queryValue(_, let occurrence):
            guard let occurrence else { return field.value }
            guard occurrence >= 0 else { return nil }
            guard let elements = arrayElements(in: field.value, text: text) else {
                return occurrence == 0 ? field.value : nil
            }
            return occurrence < elements.count ? elements[occurrence] : nil
        case .component: return nil
        }
    }

    // Duplicate JSON field names have no unambiguous source occurrence. Leave
    // their editing behavior intact, but do not link either field to the URL.
    private func uniqueField(named name: String, in text: String) -> Field? {
        var match: Field?
        for field in fields where Self.copiedText(field.key, in: text) == name {
            guard match == nil else { return nil }
            match = field
        }
        return match
    }

    private func arrayElements(in range: NSRange, text: String) -> [NSRange]? {
        let source = text as NSString
        guard source.character(at: range.location) == 91 else { return nil }
        var result: [NSRange] = []
        var start: Int?
        var end = range.location
        var depth = 0
        for token in tokens where token.range.location > range.location && token.range.location < NSMaxRange(range) {
            let c = source.character(at: token.range.location)
            if token.kind == .punctuation, depth == 0, c == 44 || c == 93 {
                if let start { result.append(NSRange(location: start, length: end - start)) }
                start = nil
                if c == 93 { break }
                continue
            }
            if start == nil { start = token.range.location }
            if token.kind == .punctuation {
                if c == 91 || c == 123 { depth += 1 }
                if c == 93 || c == 125 { depth -= 1 }
            }
            end = NSMaxRange(token.range)
        }
        return result
    }

    public static func contentRange(_ range: NSRange, in text: String) -> NSRange {
        let source = text as NSString
        if range.length >= 2, source.character(at: range.location) == 34, source.character(at: NSMaxRange(range) - 1) == 34 {
            return NSRange(location: range.location + 1, length: range.length - 2)
        }
        return range
    }
    public static func copiedText(_ range: NSRange, in text: String) -> String {
        let raw = (text as NSString).substring(with: range)
        return (try? JSONSerialization.jsonObject(with: Data(raw.utf8), options: [.fragmentsAllowed])) as? String ?? raw
    }
}
