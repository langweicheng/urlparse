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
    func testLargeURLRoundTrip() throws {
        let url = "imeituan://host/mrn?" + (0..<1000).map { "key\($0)=value%20\($0)" }.joined(separator: "&")
        let d = try URLDocument(url)
        XCTAssertEqual(try d.applying(json: d.json), url)
        measure { _ = try? URLDocument(url).json }
    }
}
