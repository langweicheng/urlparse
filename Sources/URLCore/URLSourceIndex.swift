import Foundation

/// A selection shared by the original URL, component fields, and decoded JSON.
public enum URLSelection: Equatable {
    case component(URLDocument.Component)
    case queryKey(String)
    /// A nil occurrence selects every value of a repeated parameter.
    case queryValue(String, occurrence: Int?)
}

/// Maps decoded parameter names back to UTF-16 ranges in `document.original`.
public struct URLSourceIndex {
    private struct QueryItem {
        let name: String
        let occurrence: Int
        let key: NSRange
        let value: NSRange
        let raw: NSRange
        let equals: Int?
    }

    private let components: [(URLDocument.Component, NSRange)]
    private let items: [QueryItem]
    private let length: Int

    public init(_ document: URLDocument) {
        let ranges = document.componentRanges
        var components: [(URLDocument.Component, NSRange)] = [
            (.scheme, NSRange(ranges.scheme, in: document.prefix)),
            (.path, NSRange(ranges.path, in: document.prefix))
        ]
        if let host = ranges.host { components.append((.host, NSRange(host, in: document.prefix))) }
        if !document.hash.isEmpty {
            let hashLength = document.hash.utf16.count
            components.append((.hash, NSRange(location: document.original.utf16.count - hashLength, length: hashLength)))
        }
        self.components = components
        length = document.original.utf16.count

        var items: [QueryItem] = []
        var occurrences: [String: Int] = [:]
        var offset = document.prefix.utf16.count + 1
        for item in document.items {
            let raw = item.raw as NSString
            let separator = raw.range(of: "=")
            let equals = separator.location == NSNotFound ? nil : offset + separator.location
            let keyLength = equals.map { $0 - offset } ?? raw.length
            let key = NSRange(location: offset, length: keyLength)
            let value = equals.map { NSRange(location: $0 + 1, length: raw.length - keyLength - 1) }
                ?? key
            let occurrence = occurrences[item.name, default: 0]
            items.append(QueryItem(name: item.name, occurrence: occurrence, key: key, value: value,
                                   raw: NSRange(location: offset, length: raw.length), equals: equals))
            occurrences[item.name] = occurrence + 1
            offset += raw.length + 1
        }
        self.items = items
    }

    public func ranges(for selection: URLSelection) -> [NSRange] {
        switch selection {
        case .component(let component):
            return components.filter { $0.0 == component && $0.1.length > 0 }.map { $0.1 }
        case .queryKey(let name):
            return items.filter { $0.name == name }.map { visibleRange($0.key, in: $0) }
        case .queryValue(let name, let occurrence):
            return items.filter { $0.name == name && (occurrence == nil || $0.occurrence == occurrence) }
                .map { visibleRange($0.value, in: $0) }
        }
    }

    public func selection(at offset: Int) -> URLSelection? {
        guard offset >= 0, offset < length else { return nil }
        if let component = components.first(where: { NSLocationInRange(offset, $0.1) }) {
            return .component(component.0)
        }
        for item in items {
            if NSLocationInRange(offset, item.key) { return .queryKey(item.name) }
            if offset == item.equals || (item.equals != nil && NSLocationInRange(offset, item.value)) {
                return .queryValue(item.name, occurrence: item.occurrence)
            }
            if item.raw.length == 0, offset == item.raw.location - 1 { return .queryKey(item.name) }
        }
        return nil
    }

    // Empty strings and null have no value characters in a URL. Keep a visible
    // anchor on their equals sign, bare key, or preceding query separator.
    private func visibleRange(_ range: NSRange, in item: QueryItem) -> NSRange {
        if range.length > 0 { return range }
        if let equals = item.equals { return NSRange(location: equals, length: 1) }
        return NSRange(location: item.raw.location - 1, length: 1)
    }
}
