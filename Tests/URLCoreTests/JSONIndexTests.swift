import XCTest
@testable import URLCore

final class JSONIndexTests: XCTestCase {
    func testFieldsEscapesArraysAndUnicode() throws {
        let text = #"{"城😀":"a\"b", "tags":["x,y",null], "empty":""}"#
        let index = JSONIndex(text)
        XCTAssertTrue(index.isValid)
        XCTAssertEqual(index.fields.count, 3)
        XCTAssertEqual(JSONIndex.copiedText(index.fields[0].key, in: text), "城😀")
        XCTAssertEqual(JSONIndex.copiedText(index.fields[0].value, in: text), "a\"b")
        XCTAssertEqual(JSONIndex.copiedText(index.fields[1].value, in: text), #"["x,y",null]"#)
        XCTAssertEqual(JSONIndex.contentRange(index.fields[2].value, in: text).length, 0)
    }
    func testDeleteFirstMiddleLastAndOnlyField() throws {
        for text in [#"{"a":"1","b":"2","c":"3"}"#, "{\n  \"a\": \"1\",\n  \"b\": \"2\",\n  \"c\": \"3\"\n}", #"{"a":"1"}"#] {
            let index = JSONIndex(text)
            for field in index.fields {
                let key = JSONIndex.copiedText(field.key, in: text)
                let result = (text as NSString).replacingCharacters(in: field.deletion, with: "")
                let object = try JSONSerialization.jsonObject(with: Data(result.utf8)) as! [String: Any]
                XCTAssertNil(object[key])
                XCTAssertEqual(object.count, index.fields.count - 1)
            }
        }
    }
    func testParameterDeletionDoesNotLeaveBlankLines() throws {
        for newline in ["\n", "\r\n"] {
            let lines = ["{", "  \"a\": \"1\",", "  \"b\": [", "    \"x\",", "    null", "  ],", "  \"c\": \"3\"", "}"]
            let text = lines.joined(separator: newline)
            let expected = [
                ["{", "  \"b\": [", "    \"x\",", "    null", "  ],", "  \"c\": \"3\"", "}"],
                ["{", "  \"a\": \"1\",", "  \"c\": \"3\"", "}"],
                ["{", "  \"a\": \"1\",", "  \"b\": [", "    \"x\",", "    null", "  ]", "}"]
            ]
            for (index, field) in JSONIndex(text).fields.enumerated() {
                let result = (text as NSString).replacingCharacters(in: field.deletion, with: "")
                XCTAssertEqual(result, expected[index].joined(separator: newline))
                XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(result.utf8)))
                XCTAssertEqual(TextPatch(from: text, to: result).apply(to: result, reversed: true), text)
            }
            let only = ["{", "  \"a\": \"1\"", "}"].joined(separator: newline)
            let field = try XCTUnwrap(JSONIndex(only).fields.first)
            XCTAssertEqual((only as NSString).replacingCharacters(in: field.deletion, with: ""), "{" + newline + "}")
        }
    }

    func testClearValuePreservesKeyAndOtherFields() throws {
        let text = #"{"flag":null,"tags":["a","b"],"city":"北京"}"#
        for field in JSONIndex(text).fields {
            let key = JSONIndex.copiedText(field.key, in: text)
            let result = (text as NSString).replacingCharacters(in: field.value, with: "\"\"")
            let object = try JSONSerialization.jsonObject(with: Data(result.utf8)) as! [String: Any]
            XCTAssertEqual(object[key] as? String, "")
            XCTAssertEqual(object.count, 3)
        }
    }
    func testIncompleteJSONOnlyColorsNoDestructiveActions() {
        let index = JSONIndex(#"{"key":"unfinished"#)
        XCTAssertFalse(index.isValid)
        XCTAssertTrue(index.fields.isEmpty)
        XCTAssertEqual(index.tokens.filter { $0.kind == .key }.count, 1)
    }
    func testDeletingParameterUpdatesURLAndUndoPatch() throws {
        let doc = try URLDocument("custom://host/path?a=1&b=2#frag")
        let field = JSONIndex(doc.json).fields[0]
        let changed = (doc.json as NSString).replacingCharacters(in: field.deletion, with: "")
        XCTAssertEqual(try doc.applying(json: changed), "custom://host/path?b=2#frag")
        XCTAssertEqual(TextPatch(from: doc.json, to: changed).apply(to: changed, reversed: true), doc.json)
    }

    func testSelectionsIdentifyQuotedKeysValuesAndArrayOccurrences() throws {
        let text = #"{"\u57ce😀":["a\"b", null, "😀", ""], "empty":"", "flag":null}"#
        let index = JSONIndex(text)
        let key = try XCTUnwrap(index.range(for: .queryKey("城😀"), in: text))
        XCTAssertEqual((text as NSString).substring(with: key), #""\u57ce😀""#)
        for offset in key.location..<NSMaxRange(key) { XCTAssertEqual(index.selection(at: offset, in: text), .queryKey("城😀")) }
        let expected = [#""a\"b""#, "null", #""😀""#, #""""#]
        for (occurrence, value) in expected.enumerated() {
            let selection = URLSelection.queryValue("城😀", occurrence: occurrence)
            let range = try XCTUnwrap(index.range(for: selection, in: text))
            XCTAssertEqual((text as NSString).substring(with: range), value)
            for offset in range.location..<NSMaxRange(range) { XCTAssertEqual(index.selection(at: offset, in: text), selection) }
        }
        let array = try XCTUnwrap(index.range(for: .queryValue("城😀", occurrence: nil), in: text))
        XCTAssertEqual(index.selection(at: array.location, in: text), .queryValue("城😀", occurrence: nil))
        XCTAssertEqual(index.selection(at: NSMaxRange(array) - 1, in: text), .queryValue("城😀", occurrence: nil))
        for name in ["empty", "flag"] {
            let range = try XCTUnwrap(index.range(for: .queryValue(name, occurrence: 0), in: text))
            XCTAssertEqual(index.selection(at: range.location, in: text), .queryValue(name, occurrence: 0))
            XCTAssertEqual(index.range(for: .queryValue(name, occurrence: nil), in: text), range)
            XCTAssertNil(index.range(for: .queryValue(name, occurrence: 1), in: text))
        }
        XCTAssertNil(index.range(for: .queryValue("城😀", occurrence: -1), in: text))
        XCTAssertNil(index.range(for: .queryValue("城😀", occurrence: 4), in: text))
        XCTAssertNil(index.range(for: .queryKey("missing"), in: text))
        XCTAssertNil(index.range(for: .component(.host), in: text))
        XCTAssertNil(index.selection(at: 0, in: text))
        XCTAssertNil(index.selection(at: text.utf16.count, in: text))
    }

    func testArrayWhitespaceAndNestedTokensDoNotChangeOccurrenceNumbers() throws {
        let text = #"{"a": [ "first", ["nested",null], {"x":"y"}, "last" ], "empty":[]}"#
        let index = JSONIndex(text)
        for (occurrence, value) in [#""first""#, #"["nested",null]"#, #"{"x":"y"}"#, #""last""#].enumerated() {
            let range = try XCTUnwrap(index.range(for: .queryValue("a", occurrence: occurrence), in: text))
            XCTAssertEqual((text as NSString).substring(with: range), value)
            XCTAssertEqual(index.selection(at: range.location, in: text), .queryValue("a", occurrence: occurrence))
        }
        let comma = (text as NSString).range(of: #"", ["#).location + 1
        XCTAssertEqual(index.selection(at: comma, in: text), .queryValue("a", occurrence: nil))
        XCTAssertNil(index.range(for: .queryValue("empty", occurrence: 0), in: text))
        XCTAssertEqual((text as NSString).substring(with: try XCTUnwrap(index.range(for: .queryValue("empty", occurrence: nil), in: text))), "[]")
    }

    func testInvalidJSONHasNoSelections() {
        let text = #"{"name": ["first","#
        let index = JSONIndex(text)
        XCTAssertNil(index.selection(at: 3, in: text))
        XCTAssertNil(index.range(for: .queryKey("name"), in: text))
    }

    func testDuplicateJSONKeysDisableOnlyTheirAmbiguousMappings() throws {
        for secondKey in [#""a""#, #""\u0061""#] {
            let text = #"{"a":"first", "other":"kept", "# + secondKey + #":["last",null]}"#
            let index = JSONIndex(text)
            XCTAssertTrue(index.isValid)
            XCTAssertEqual(index.fields.count, 3)
            for field in [index.fields[0], index.fields[2]] {
                for offset in field.range.location..<NSMaxRange(field.range) {
                    XCTAssertNil(index.selection(at: offset, in: text))
                }
            }
            XCTAssertNil(index.range(for: .queryKey("a"), in: text))
            XCTAssertNil(index.range(for: .queryValue("a", occurrence: 0), in: text))
            XCTAssertNil(index.range(for: .queryValue("a", occurrence: nil), in: text))
            let other = index.fields[1]
            XCTAssertEqual(index.range(for: .queryKey("other"), in: text), other.key)
            XCTAssertEqual(index.selection(at: other.value.location, in: text), .queryValue("other", occurrence: 0))
            XCTAssertNoThrow(try URLDocument("custom://host?a=before").applying(json: text))
        }
    }
}
