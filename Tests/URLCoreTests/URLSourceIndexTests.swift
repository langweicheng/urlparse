import XCTest
@testable import URLCore

final class URLSourceIndexTests: XCTestCase {
    func testComponentRangesUseOriginalUTF16AndExcludeCredentialsAndPort() throws {
        let document = try URLDocument("custom://user:p%40ss@[2001:db8::1]:8443/城😀/%2f?city=北京#frag?x=1")
        let index = URLSourceIndex(document)
        for (component, expected) in [(URLDocument.Component.scheme, "custom"), (.host, "[2001:db8::1]"), (.path, "/城😀/%2f"), (.hash, "#frag?x=1")] {
            XCTAssertEqual(substrings(index.ranges(for: .component(component)), in: document.original), [expected])
            for range in index.ranges(for: .component(component)) {
                for offset in range.location..<NSMaxRange(range) {
                    XCTAssertEqual(index.selection(at: offset), .component(component))
                }
            }
        }
        for excluded in ["user", "p%40ss", "8443"] {
            let range = (document.original as NSString).range(of: excluded)
            for offset in range.location..<NSMaxRange(range) { XCTAssertNil(index.selection(at: offset), excluded) }
        }
        XCTAssertNil(index.selection(at: -1))
        XCTAssertNil(index.selection(at: document.original.utf16.count))
    }

    func testDuplicateDecodedNamesAndValuesKeepExactOccurrences() throws {
        let document = try URLDocument("https://host/😀?na%6De=one&other=1&name=%E5%8C%97%E4%BA%AC&name=😀=two&name&name=#tail")
        let index = URLSourceIndex(document)
        XCTAssertEqual(substrings(index.ranges(for: .queryKey("name")), in: document.original), ["na%6De", "name", "name", "name", "name"])
        let expected = ["one", "%E5%8C%97%E4%BA%AC", "😀=two", "name", "="]
        XCTAssertEqual(substrings(index.ranges(for: .queryValue("name", occurrence: nil)), in: document.original), expected)
        for (occurrence, value) in expected.enumerated() {
            XCTAssertEqual(substrings(index.ranges(for: .queryValue("name", occurrence: occurrence)), in: document.original), [value])
        }
        for occurrence in [0, 1, 2, 4] {
            let range = try XCTUnwrap(index.ranges(for: .queryValue("name", occurrence: occurrence)).first)
            for offset in range.location..<NSMaxRange(range) {
                XCTAssertEqual(index.selection(at: offset), .queryValue("name", occurrence: occurrence))
            }
        }
        for range in index.ranges(for: .queryKey("name")) {
            XCTAssertEqual(index.selection(at: range.location), .queryKey("name"))
        }
        XCTAssertTrue(index.ranges(for: .queryValue("name", occurrence: -1)).isEmpty)
        XCTAssertTrue(index.ranges(for: .queryValue("name", occurrence: 5)).isEmpty)
        XCTAssertTrue(index.ranges(for: .queryKey("missing")).isEmpty)
    }

    func testEmptyAndBareValuesHaveVisibleAnchors() throws {
        let document = try URLDocument("https://host?empty=&flag&=v&&=&#fragment")
        let index = URLSourceIndex(document)
        XCTAssertEqual(substrings(index.ranges(for: .queryValue("empty", occurrence: 0)), in: document.original), ["="])
        XCTAssertEqual(substrings(index.ranges(for: .queryValue("flag", occurrence: 0)), in: document.original), ["flag"])
        XCTAssertEqual(substrings(index.ranges(for: .queryKey("")), in: document.original), ["=", "&", "=", "&"])
        XCTAssertEqual(substrings(index.ranges(for: .queryValue("", occurrence: nil)), in: document.original), ["v", "&", "=", "&"])
        for offset in (document.original as NSString).range(of: "#fragment").location..<document.original.utf16.count {
            XCTAssertEqual(index.selection(at: offset), .component(.hash))
        }
    }

    func testOpaqueAndEmptyComponents() throws {
        for url in ["mailto:me@example.com?subject=hello", "custom:城😀?x=1", "file:///tmp/a?", "custom://host"] {
            let document = try URLDocument(url)
            let index = URLSourceIndex(document)
            XCTAssertEqual(substrings(index.ranges(for: .component(.scheme)), in: url), [document.scheme])
            XCTAssertEqual(substrings(index.ranges(for: .component(.host)), in: url), document.host.isEmpty ? [] : [document.host])
            XCTAssertEqual(substrings(index.ranges(for: .component(.path)), in: url), document.path.isEmpty ? [] : [document.path])
            XCTAssertTrue(index.ranges(for: .component(.hash)).isEmpty)
        }
        let noQuery = try URLDocument("custom:hello#?name=value")
        XCTAssertTrue(URLSourceIndex(noQuery).ranges(for: .queryKey("name")).isEmpty)
    }

    func testHashSelectionIncludesDelimiterUnicodeAndRouteParameters() throws {
        for hash in ["#", "#城😀/%2f?name=value&name=two#detail"] {
            let document = try URLDocument("custom:城😀?name=original" + hash)
            let index = URLSourceIndex(document)
            let range = try XCTUnwrap(index.ranges(for: .component(.hash)).first)
            XCTAssertEqual(substrings([range], in: document.original), [hash])
            for offset in range.location..<NSMaxRange(range) {
                XCTAssertEqual(index.selection(at: offset), .component(.hash))
            }
            XCTAssertEqual(substrings(index.ranges(for: .queryKey("name")), in: document.original), ["name"])
            XCTAssertEqual(substrings(index.ranges(for: .queryValue("name", occurrence: nil)), in: document.original), ["original"])
            XCTAssertEqual(index.selection(at: range.location - 1), .queryValue("name", occurrence: 0))
        }
    }

    func testURLAndJSONSelectionRoundTripsWithEncodedAndUnicodeKeys() throws {
        let document = try URLDocument("custom://host/😀?%E5%9F%8E%F0%9F%98%80=%22x%22&plain=a&%E5%9F%8E%F0%9F%98%80=😀&flag&empty=")
        let source = URLSourceIndex(document)
        let json = document.json
        let index = JSONIndex(json)
        for selection in [URLSelection.queryKey("城😀"), .queryValue("城😀", occurrence: 0), .queryValue("城😀", occurrence: 1),
                          .queryKey("plain"), .queryValue("plain", occurrence: 0), .queryKey("flag"), .queryValue("empty", occurrence: 0)] {
            let range = try XCTUnwrap(index.range(for: selection, in: json))
            XCTAssertEqual(index.selection(at: range.location, in: json), selection)
            for range in source.ranges(for: selection) { XCTAssertEqual(source.selection(at: range.location), selection) }
        }
    }

    private func substrings(_ ranges: [NSRange], in text: String) -> [String] {
        ranges.map { (text as NSString).substring(with: $0) }
    }
}
