import XCTest
@testable import URLCore

final class TextPatchTests: XCTestCase {
    func testRoundTripsUnicodeAndEditingBoundaries() {
        let values = ["", "a", "abc", "axc", "北京", "👨‍👩‍👧‍👦", "😀", "😁", "a😀z", "a😁z", "e\u{301}", "é", "\r\n", "\n"]
        for old in values {
            for new in values {
                let patch = TextPatch(from: old, to: new)
                XCTAssertEqual(patch.apply(to: old), new)
                XCTAssertEqual(patch.apply(to: new, reversed: true), old)
            }
        }
    }
    func testSmallEditDoesNotRetainEntireDocument() {
        let old = String(repeating: "x", count: 100_000)
        let patch = TextPatch(from: old, to: old + "y")
        XCTAssertEqual(patch.removed.utf8.count + patch.inserted.utf8.count, 1)
        XCTAssertEqual(patch.apply(to: old), old + "y")
    }
    func testUndoRedoSequenceWithInvalidJSON() {
        let states = ["{}", "{", "{\"city\":\"北京\"}", "{\"city\":\"😀\"}", ""]
        let patches = zip(states, states.dropFirst()).map { TextPatch(from: $0.0, to: $0.1) }
        var text = states.last!
        for (patch, expected) in zip(patches.reversed(), states.dropLast().reversed()) {
            text = patch.apply(to: text, reversed: true)
            XCTAssertEqual(text, expected)
        }
        for (patch, expected) in zip(patches, states.dropFirst()) {
            text = patch.apply(to: text)
            XCTAssertEqual(text, expected)
        }
    }
}
