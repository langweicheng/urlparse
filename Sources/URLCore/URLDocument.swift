import Foundation

public struct URLDocument {
    struct Item { let raw: String; let name: String; let value: String? }
    let prefix: String
    let fragment: String
    let hadQuery: Bool
    let items: [Item]
    public let original: String

    public init(_ input: String) throws {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let components = URLComponents(string: text),
              let scheme = components.scheme, !scheme.isEmpty else {
            throw Failure("请输入带协议的 URL，例如 https://example.com 或 imeituan://…")
        }
        original = text
        let split = text.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        fragment = split.count == 2 ? "#" + split[1] : ""
        let parts = split[0].split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        prefix = String(parts[0]); hadQuery = parts.count == 2
        items = try parts.count == 2 && !parts[1].isEmpty ? parts[1].split(separator: "&", omittingEmptySubsequences: false).map { piece in
            let pair = piece.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = String(pair[0]).removingPercentEncoding else { throw Failure("参数名包含无效的百分号编码") }
            var value: String? = nil
            if pair.count == 2 {
                guard let decoded = String(pair[1]).removingPercentEncoding else { throw Failure("参数值包含无效的百分号编码") }
                value = decoded
            }
            return Item(raw: String(piece), name: key, value: value)
        } : []
    }

    public var json: String {
        var result: [String: Any] = [:]
        for item in items {
            let value: Any = item.value.map { $0 as Any } ?? NSNull()
            if let existing = result[item.name] {
                if var array = existing as? [Any] { array.append(value); result[item.name] = array }
                else { result[item.name] = [existing, value] }
            } else { result[item.name] = value }
        }
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    public enum Component: Equatable { case scheme, host, path, hash }

    // Work on the original prefix so editing one component never normalizes
    // credentials, port, query encoding, or fragment elsewhere in the URL.
    var componentRanges: (scheme: Range<String.Index>, host: Range<String.Index>?, path: Range<String.Index>) {
        let colon = prefix.firstIndex(of: ":")!
        let afterScheme = prefix.index(after: colon)
        guard prefix[afterScheme...].hasPrefix("//") else {
            return (prefix.startIndex..<colon, nil, afterScheme..<prefix.endIndex)
        }
        let authorityStart = prefix.index(afterScheme, offsetBy: 2)
        let authorityEnd = prefix[authorityStart...].firstIndex(of: "/") ?? prefix.endIndex
        let authority = authorityStart..<authorityEnd
        let hostStart = prefix[authority].lastIndex(of: "@").map { prefix.index(after: $0) } ?? authorityStart
        let hostEnd: String.Index
        if prefix[hostStart..<authorityEnd].hasPrefix("["), let bracket = prefix[hostStart..<authorityEnd].firstIndex(of: "]") {
            hostEnd = prefix.index(after: bracket)
        } else {
            hostEnd = prefix[hostStart..<authorityEnd].firstIndex(of: ":") ?? authorityEnd
        }
        return (prefix.startIndex..<colon, hostStart..<hostEnd, authorityEnd..<prefix.endIndex)
    }

    public var scheme: String { String(prefix[componentRanges.scheme]) }
    public var host: String { componentRanges.host.map { String(prefix[$0]) } ?? "" }
    public var path: String { String(prefix[componentRanges.path]) }
    public var hash: String { fragment }

    public func applying(component: Component, value: String) throws -> String {
        let ranges = componentRanges
        let range: Range<String.Index>
        let replacement: String
        switch component {
        case .scheme:
            guard value.range(of: "^[A-Za-z][A-Za-z0-9+.-]*$", options: .regularExpression) != nil else {
                throw Failure("协议须以字母开头，只能包含字母、数字、+、-、.，不含 ://")
            }
            range = ranges.scheme; replacement = value
        case .host:
            guard let hostRange = ranges.host else { throw Failure("此 URL 没有 // Host 部分，请在左侧修改 URL 结构") }
            guard let c = URLComponents(string: "x://" + value), c.host != nil,
                  c.user == nil, c.password == nil, c.port == nil,
                  c.path.isEmpty, c.query == nil, c.fragment == nil,
                  !value.contains(":") || (value.hasPrefix("[") && value.hasSuffix("]")),
                  !value.contains("\\"), value.removingPercentEncoding != nil else {
                throw Failure("Host 仅填写主机名或方括号内的 IPv6 地址，不含协议、端口或路径")
            }
            range = hostRange; replacement = value
        case .path:
            guard value.removingPercentEncoding != nil else { throw Failure("路径包含无效的百分号编码") }
            var allowed = CharacterSet.urlPathAllowed
            allowed.insert(charactersIn: "%")
            allowed.remove(charactersIn: "?#")
            var encoded = value.addingPercentEncoding(withAllowedCharacters: allowed)!
            if ranges.host != nil, !encoded.isEmpty, !encoded.hasPrefix("/") { encoded = "/" + encoded }
            range = ranges.path; replacement = encoded
        case .hash:
            let content = value.hasPrefix("#") ? String(value.dropFirst()) : value
            guard content.removingPercentEncoding != nil else { throw Failure("Hash 包含无效的百分号编码") }
            var allowed = CharacterSet.urlFragmentAllowed
            allowed.insert(charactersIn: "%#")
            let encoded = content.addingPercentEncoding(withAllowedCharacters: allowed)!
            let result = String(original.dropLast(fragment.count)) + (value.isEmpty ? "" : "#" + encoded)
            _ = try URLDocument(result)
            return result
        }
        var changedPrefix = prefix
        changedPrefix.replaceSubrange(range, with: replacement)
        let result = changedPrefix + original.dropFirst(prefix.count)
        _ = try URLDocument(result)
        return result
    }

    public func applying(json: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        guard let dict = object as? [String: Any] else { throw Failure("顶层必须是 JSON 对象") }
        var values: [String: [String?]] = [:]
        for (key, value) in dict {
            let list = (value as? [Any]) ?? [value]
            guard !list.isEmpty else { throw Failure("重复参数数组不能为空；删除参数请删除整个字段") }
            values[key] = try list.map { element in
                if element is NSNull { return nil }
                guard let string = element as? String else { throw Failure("参数值请使用字符串、null 或字符串数组，以保留 URL 原始语义") }
                return string
            }
        }
        var offsets: [String: Int] = [:]
        var result: [String] = []
        func encoded(_ name: String, _ value: String?) -> String {
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
            let key = name.addingPercentEncoding(withAllowedCharacters: allowed)!
            return value.map { key + "=" + $0.addingPercentEncoding(withAllowedCharacters: allowed)! } ?? key
        }
        for item in items {
            let index = offsets[item.name, default: 0]
            guard let list = values[item.name], index < list.count else { continue }
            let next = list[index]
            result.append(next == item.value ? item.raw : encoded(item.name, next))
            offsets[item.name] = index + 1
        }
        for key in values.keys.sorted() {
            let list = values[key]!
            for value in list.dropFirst(offsets[key, default: 0]) { result.append(encoded(key, value)) }
        }
        return prefix + (result.isEmpty ? (hadQuery && items.isEmpty ? "?" : "") : "?" + result.joined(separator: "&")) + fragment
    }
}

public struct Failure: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
