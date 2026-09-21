import XCTest
@testable import URLCore

final class URLDocumentTests: XCTestCase {
    func testDecodedJSON() throws {
        let d = try URLDocument("imeituan://www.meituan.com/mrn?name=%E9%85%92%E5%BA%97&empty=&flag&n=001&plus=a+b#section")
        let json = try JSONSerialization.jsonObject(with: Data(d.json.utf8)) as! [String: Any]
        XCTAssertEqual(json["name"] as? String, "酒店")
        XCTAssertEqual(json["empty"] as? String, "")
        XCTAssertTrue(json["flag"] is NSNull)
        XCTAssertEqual(json["n"] as? String, "001")
        XCTAssertEqual(json["plus"] as? String, "a+b")
        XCTAssertEqual(try d.applying(json: d.json), d.original)
    }
    func testEditAddRemoveAndEncoding() throws {
        let d = try URLDocument("custom://host/path?a=1&keep=%2f&remove=x#fragment")
        XCTAssertEqual(try d.applying(json: "{\"a\":\"中文 &=+#\",\"keep\":\"/\",\"new\":\"yes\"}"), "custom://host/path?a=%E4%B8%AD%E6%96%87%20%26%3D%2B%23&keep=%2f&new=yes#fragment")
    }
    func testDuplicateKeysAndOrder() throws {
        let d = try URLDocument("https://host/?a=1&b=x&a=2&a")
        XCTAssertEqual(try d.applying(json: d.json), d.original)
        XCTAssertEqual(try d.applying(json: "{\"a\":[\"1\",\"3\"],\"b\":\"x\"}"), "https://host/?a=1&b=x&a=3")
        XCTAssertEqual(try d.applying(json: "{\"a\":[\"1\",\"2\",null,\"4\"],\"b\":\"x\"}"), "https://host/?a=1&b=x&a=2&a&a=4")
    }
    func testInvalidInputs() throws {
        XCTAssertThrowsError(try URLDocument("not a URL"))
        XCTAssertThrowsError(try URLDocument("https://x/?a=%FF"))
        let d = try URLDocument("https://host/?a=1")
        for input in ["{", "[]", "{\"a\":1}", "{\"a\":[]}", "{\"a\":{}}"] {
            XCTAssertThrowsError(try d.applying(json: input))
        }
    }
    func testNoQueryAndFragment() throws {
        for url in ["https://host/path#?q=1", "https://host/path?", "custom:hello", "https://host/?=x&&a=b=c", "https://host/?x=%252F"] {
            let d = try URLDocument(url)
            XCTAssertEqual(try d.applying(json: d.json), url)
        }
        let d = try URLDocument("https://host/path#frag")
        XCTAssertEqual(try d.applying(json: "{\"x\":\"y\"}"), "https://host/path?x=y#frag")
    }
    func testComponentEditingPreservesUntouchedURLBytes() throws {
        let original = "custom://user:p%40ss@old.example:8443/a%2fb?x=%2f&x=two+words&flag#raw%2f"
        let d = try URLDocument(original)
        XCTAssertEqual(d.scheme, "custom")
        XCTAssertEqual(d.host, "old.example")
        XCTAssertEqual(d.path, "/a%2fb")
        XCTAssertEqual(try d.applying(component: .scheme, value: "https"), original.replacingOccurrences(of: "custom:", with: "https:"))
        XCTAssertEqual(try d.applying(component: .host, value: "new.example"), original.replacingOccurrences(of: "old.example", with: "new.example"))
        XCTAssertEqual(try d.applying(component: .path, value: "/new%2fpath"), original.replacingOccurrences(of: "/a%2fb", with: "/new%2fpath"))
        let changed = try URLDocument(d.applying(component: .host, value: "[2001:db8::1]"))
        XCTAssertEqual(changed.host, "[2001:db8::1]")
        XCTAssertTrue(try changed.applying(component: .host, value: "next.example").contains("@next.example:8443/"))
        XCTAssertEqual(try d.applying(component: .path, value: ""), original.replacingOccurrences(of: "/a%2fb", with: ""))
    }
    func testComponentEncodingAndValidation() throws {
        let d = try URLDocument("https://host/path?x=%252F#frag")
        XCTAssertEqual(try d.applying(component: .path, value: "中文 a?#"), "https://host/%E4%B8%AD%E6%96%87%20a%3F%23?x=%252F#frag")
        for scheme in ["", "1http", "https://", "a b", "a\n"] {
            XCTAssertThrowsError(try d.applying(component: .scheme, value: scheme))
        }
        for host in ["bad host", "host:80", "user@host", "host/path", "host?x=1", "host#fragment", "[::1", "host%ZZ"] {
            XCTAssertThrowsError(try d.applying(component: .host, value: host), host)
        }
        XCTAssertThrowsError(try d.applying(component: .path, value: "/bad%ZZ"))
        let opaque = try URLDocument("custom:hello?x=1#f")
        XCTAssertEqual(opaque.host, "")
        XCTAssertEqual(try opaque.applying(component: .path, value: "world"), "custom:world?x=1#f")
        XCTAssertThrowsError(try opaque.applying(component: .host, value: "host"))
        let emptyQuery = try URLDocument("file:///tmp/a?#f")
        XCTAssertEqual(try emptyQuery.applying(component: .path, value: "/tmp/b"), "file:///tmp/b?#f")
    }
    func testHashParsingKeepsRawFragmentSeparateFromQuery() throws {
        for hash in ["", "#", "#section", "#/route?tab=one&name=%E4%B8%AD%E6%96%87#detail", "#中文😀"] {
            let d = try URLDocument("custom://host/path?keep=%2f" + hash)
            XCTAssertEqual(d.hash, hash)
            let json = try JSONSerialization.jsonObject(with: Data(d.json.utf8)) as! [String: String]
            XCTAssertEqual(json, ["keep": "/"])
            XCTAssertEqual(try d.applying(json: d.json), d.original)
        }
        let hashOnly = try URLDocument("custom:hello#?x=1&y=2")
        XCTAssertEqual(hashOnly.hash, "#?x=1&y=2")
        XCTAssertTrue(hashOnly.items.isEmpty)
    }
    func testHashEditingPreservesUntouchedURLBytes() throws {
        let base = "CUSTOM://user:p%40ss@old.example:8443/城😀/%2fb?x=%2f&x=two+words&flag"
        for hash in ["", "#", "#old?x=1#detail"] {
            let d = try URLDocument(base + hash)
            for value in ["#new", "new"] {
                XCTAssertEqual(try d.applying(component: .hash, value: value), base + "#new")
            }
            XCTAssertEqual(try d.applying(component: .hash, value: ""), base)
            XCTAssertEqual(try d.applying(component: .hash, value: "#"), base + "#")
        }
        let emptyQuery = try URLDocument("file:///tmp/a?#old")
        XCTAssertEqual(try emptyQuery.applying(component: .hash, value: "new"), "file:///tmp/a?#new")
        XCTAssertEqual(try emptyQuery.applying(component: .hash, value: ""), "file:///tmp/a?")
        XCTAssertEqual(try URLDocument("custom:hello").applying(component: .hash, value: "section"), "custom:hello#section")
    }
    func testHashEncodingAndValidation() throws {
        let d = try URLDocument("https://host/path?x=%252F#old")
        let changed = try d.applying(component: .hash, value: "#/中文 a?tab=one&next=%2f+%252F#detail")
        XCTAssertEqual(changed, "https://host/path?x=%252F#/%E4%B8%AD%E6%96%87%20a?tab=one&next=%2f+%252F#detail")
        let parsed = try URLDocument(changed)
        XCTAssertEqual(parsed.hash, "#/%E4%B8%AD%E6%96%87%20a?tab=one&next=%2f+%252F#detail")
        XCTAssertEqual(parsed.json, d.json)
        XCTAssertEqual(try parsed.applying(component: .hash, value: parsed.hash), changed)
        for hash in ["#bad%", "%2", "#bad%ZZ", "#%FF"] {
            XCTAssertThrowsError(try d.applying(component: .hash, value: hash), hash)
        }
    }
    func testLargeURLRoundTrip() throws {
        let url = "imeituan://host/mrn?" + (0..<1000).map { "key\($0)=value%20\($0)" }.joined(separator: "&")
        let d = try URLDocument(url)
        XCTAssertEqual(try d.applying(json: d.json), url)
        measure { _ = try? URLDocument(url).json }
    }
}
