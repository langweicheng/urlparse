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
}
