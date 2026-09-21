import XCTest
import AppKit
@testable import URLParser

final class LinkageTests: XCTestCase {
    private func makeEditor(_ url: String) -> AppDelegate {
        _ = NSApplication.shared
        let app = AppDelegate()
        app.history.groupsByEvent = false
        edit(app) {
            app.left.string = url
            app.textDidChange(Notification(name: NSText.didChangeNotification, object: app.left))
        }
        app.history.removeAllActions()
        return app
    }

    private func edit(_ app: AppDelegate, _ action: () -> Void) {
        app.history.beginUndoGrouping()
        action()
        app.history.endUndoGrouping()
    }

    private func range(_ text: String, in source: String, occurrence: Int = 0,
                       file: StaticString = #filePath, line: UInt = #line) -> NSRange {
        let source = source as NSString
        var search = NSRange(location: 0, length: source.length)
        var match = NSRange(location: NSNotFound, length: 0)
        for _ in 0...occurrence {
            match = source.range(of: text, range: search)
            guard match.location != NSNotFound else {
                XCTFail("Missing \(text) in \(source)", file: file, line: line)
                return NSRange(location: 0, length: 0)
            }
            search = NSRange(location: NSMaxRange(match), length: source.length - NSMaxRange(match))
        }
        return match
    }

    private func select(_ text: String, in view: EditorTextView, occurrence: Int = 0) {
        let token = range(text, in: view.string, occurrence: occurrence)
        view.setSelectedRange(NSRange(location: token.location + min(1, max(0, token.length - 1)), length: 0))
    }

    private func assertHighlights(_ view: EditorTextView, _ expected: [NSRange],
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(view.linkedHighlightRanges, expected, file: file, line: line)
        let length = (view.string as NSString).length
        for highlight in expected {
            guard highlight.location != NSNotFound, highlight.length > 0,
                  NSMaxRange(highlight) <= length else {
                XCTFail("Highlight is outside the current text: \(highlight)", file: file, line: line)
                continue
            }
            for position in highlight.location..<NSMaxRange(highlight) {
                XCTAssertNotNil(view.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: position, effectiveRange: nil),
                                "Missing visible highlight at \(position)", file: file, line: line)
            }
        }
    }

    private func assertNoLinkedHighlights(_ app: AppDelegate,
                                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.left.linkedHighlightRanges.isEmpty, file: file, line: line)
        XCTAssertTrue(app.right.linkedHighlightRanges.isEmpty, file: file, line: line)
        XCTAssertTrue(app.componentFields.allSatisfy { !$0.isLinkedHighlighted }, file: file, line: line)
        for view in [app.left, app.right] {
            for position in 0..<(view.string as NSString).length {
                XCTAssertNil(view.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: position, effectiveRange: nil),
                             "Stale highlight at \(position)", file: file, line: line)
            }
        }
    }

    func testProtocolHostPathAndHashLinkInBothDirectionsWithoutEditing() {
        let app = makeEditor("https://user:pass@example.com:8443/a%20b?q=value#fragment")
        let originalURL = app.left.string
        let originalJSON = app.right.string
        app.left.setSelectedRange(NSRange(location: 3, length: 2))
        app.right.setSelectedRange(NSRange(location: 0, length: 0))
        let leftSelection = app.left.selectedRange()
        let rightSelection = app.right.selectedRange()

        for (index, text) in ["https", "example.com", "/a%20b", "#fragment"].enumerated() {
            let expected = range(text, in: originalURL)
            app.updateLinkedSelection(from: .component(index), scroll: false)
            assertHighlights(app.left, [expected])
            assertHighlights(app.right, [])
            XCTAssertEqual(app.componentFields.map(\.isLinkedHighlighted), (0..<4).map { $0 == index })
            XCTAssertEqual(app.left.selectedRange(), leftSelection)
            XCTAssertEqual(app.right.selectedRange(), rightSelection)

            select(text, in: app.left)
            app.updateLinkedSelection(from: .url, scroll: false)
            assertHighlights(app.left, [expected])
            XCTAssertEqual(app.componentFields.map(\.isLinkedHighlighted), (0..<4).map { $0 == index })
            app.left.setSelectedRange(leftSelection)
        }
        XCTAssertEqual(app.left.string, originalURL)
        XCTAssertEqual(app.right.string, originalJSON)
        XCTAssertFalse(app.history.canUndo)
        XCTAssertFalse(app.history.canRedo)
    }

    func testJSONKeyAndValueLocateOriginalPercentEncodedText() {
        let app = makeEditor("https://example.com/path?na%6De=hello%20world&other=x")
        let originalURL = app.left.string
        let originalJSON = app.right.string
        app.left.setSelectedRange(NSRange(location: 1, length: 2))
        let leftSelection = app.left.selectedRange()

        for (json, raw) in [("\"name\"", "na%6De"), ("\"hello world\"", "hello%20world")] {
            select(json, in: app.right)
            let rightSelection = app.right.selectedRange()
            app.updateLinkedSelection(from: .json, scroll: false)
            assertHighlights(app.left, [range(raw, in: originalURL)])
            assertHighlights(app.right, [range(json, in: originalJSON)])
            XCTAssertEqual(app.left.selectedRange(), leftSelection)
            XCTAssertEqual(app.right.selectedRange(), rightSelection)
            XCTAssertTrue(app.componentFields.allSatisfy { !$0.isLinkedHighlighted })
        }

        select("%20", in: app.left)
        app.updateLinkedSelection(from: .url, scroll: false)
        assertHighlights(app.left, [range("hello%20world", in: originalURL)])
        assertHighlights(app.right, [range("\"hello world\"", in: originalJSON)])
        XCTAssertEqual(app.left.string, originalURL)
        XCTAssertEqual(app.right.string, originalJSON)
        XCTAssertFalse(app.history.canUndo)
    }

    func testHashLinksFromFieldAndEveryFragmentCharacterUsingUTF16Offsets() {
        let hash = "#/酒店😀?tab=detail&token=%2f"
        let app = makeEditor(" \t\nhttps://example.com/😀?token=%2f" + hash + " \n")
        let expected = range(hash, in: app.left.string)
        let originalURL = app.left.string
        let originalJSON = app.right.string
        app.updateLinkedSelection(from: .component(3), scroll: false)
        assertHighlights(app.left, [expected])
        assertHighlights(app.right, [])
        XCTAssertEqual(app.componentFields.map(\.isLinkedHighlighted), [false, false, false, true])

        // Include the # delimiter, both UTF-16 units of the emoji, and encoded text.
        for position in expected.location..<NSMaxRange(expected) {
            app.left.setSelectedRange(NSRange(location: position, length: 0))
            app.updateLinkedSelection(from: .url, scroll: false)
            assertHighlights(app.left, [expected])
            assertHighlights(app.right, [])
            XCTAssertEqual(app.componentFields.map(\.isLinkedHighlighted), [false, false, false, true])
        }
        select("%2f", in: app.left)
        app.updateLinkedSelection(from: .url, scroll: false)
        assertHighlights(app.left, [range("%2f", in: app.left.string)])
        assertHighlights(app.right, [range("\"/\"", in: app.right.string)])
        XCTAssertFalse(app.hashField.isLinkedHighlighted)
        XCTAssertEqual(app.left.string, originalURL)
        XCTAssertEqual(app.right.string, originalJSON)
        XCTAssertFalse(app.history.canUndo)
    }

    func testHashFocusAndTrailingGlyphClickTriggerLinkage() {
        let app = makeEditor("https://example.com/path?key=value#section")
        let expected = range("#section", in: app.left.string)
        select("\"value\"", in: app.right)
        app.updateLinkedSelection(from: .json, scroll: false)
        app.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: app.hashField))
        assertHighlights(app.left, [expected])
        assertHighlights(app.right, [])
        XCTAssertTrue(app.hashField.isLinkedHighlighted)

        app.clearLinkedHighlights()
        app.hashField.onInteraction?()
        assertHighlights(app.left, [expected])
        XCTAssertTrue(app.hashField.isLinkedHighlighted)

        clickRightHalf(ofCharacter: NSMaxRange(expected) - 1, in: app.left)
        assertHighlights(app.left, [expected])
        assertHighlights(app.right, [])
        XCTAssertTrue(app.hashField.isLinkedHighlighted)
    }

    func testEmptyHashMarkerLinksAndAbsentHashHasNoURLHighlight() {
        let app = makeEditor("https://example.com/path?key=value#")
        let marker = range("#", in: app.left.string)
        app.updateLinkedSelection(from: .component(3), scroll: false)
        assertHighlights(app.left, [marker])
        app.left.setSelectedRange(NSRange(location: marker.location, length: 0))
        app.updateLinkedSelection(from: .url, scroll: false)
        assertHighlights(app.left, [marker])
        assertHighlights(app.right, [])
        XCTAssertTrue(app.hashField.isLinkedHighlighted)

        edit(app) {
            app.hashField.stringValue = ""
            app.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: app.hashField))
        }
        app.updateLinkedSelection(from: .component(3), scroll: false)
        assertHighlights(app.left, [])
        assertHighlights(app.right, [])
        app.left.setSelectedRange(NSRange(location: (app.left.string as NSString).length, length: 0))
        app.updateLinkedSelection(from: .url, scroll: false)
        assertNoLinkedHighlights(app)
    }

    func testSelectionNotificationsAndComponentFocusTriggerLinkage() {
        let app = makeEditor("https://example.com/path?key=value")
        select("key", in: app.left)
        app.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: app.left))
        assertHighlights(app.right, [range("\"key\"", in: app.right.string)])

        select("\"value\"", in: app.right)
        app.right.didInteract()
        assertHighlights(app.left, [range("value", in: app.left.string)])

        app.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: app.hostField))
        assertHighlights(app.left, [range("example.com", in: app.left.string)])
        XCTAssertTrue(app.hostField.isLinkedHighlighted)
        assertHighlights(app.right, [])
    }

    func testClickingRightHalfOfLastGlyphLinksTheCharacterInsteadOfTrailingCaret() {
        let app = makeEditor("https://example.com/?key=value")
        let value = range("value", in: app.left.string)
        clickRightHalf(ofCharacter: NSMaxRange(value) - 1, in: app.left)
        assertHighlights(app.left, [value])
        assertHighlights(app.right, [range("\"value\"", in: app.right.string)])

        let jsonValue = range("\"value\"", in: app.right.string)
        clickRightHalf(ofCharacter: NSMaxRange(jsonValue) - 1, in: app.right)
        assertHighlights(app.left, [value])
        assertHighlights(app.right, [jsonValue])

        let hostApp = makeEditor("https://example.com")
        let host = range("example.com", in: hostApp.left.string)
        clickRightHalf(ofCharacter: NSMaxRange(host) - 1, in: hostApp.left)
        assertHighlights(hostApp.left, [host])
        XCTAssertTrue(hostApp.hostField.isLinkedHighlighted)
        assertHighlights(hostApp.right, [])
    }

    private func clickRightHalf(ofCharacter position: Int, in view: EditorTextView,
                                file: StaticString = #filePath, line: UInt = #line) {
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 240)
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        let layout = view.layoutManager!
        layout.ensureLayout(for: view.textContainer!)
        let glyph = layout.glyphIndexForCharacter(at: position)
        let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: view.textContainer!)
        let point = NSPoint(x: rect.maxX - rect.width * 0.2 + view.textContainerOrigin.x,
                           y: rect.midY + view.textContainerOrigin.y)
        let caret = view.characterIndexForInsertion(at: point)
        XCTAssertEqual(caret, position + 1, "The click should place the caret after this glyph", file: file, line: line)
        view.setSelectedRange(NSRange(location: caret, length: 0))
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(point, to: nil), modifierFlags: [],
                                      timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        let clicked = view.clickedCharacterIndex(for: event)
        XCTAssertEqual(clicked, position, file: file, line: line)
        view.didInteract(at: clicked)
        XCTAssertEqual(view.selectedRange(), NSRange(location: caret, length: 0), file: file, line: line)
        XCTAssertNil(view.interactionPosition, file: file, line: line)
    }

    func testRepeatedValuesLinkToTheirArrayOccurrenceAndKeysToAllOccurrences() {
        let app = makeEditor("https://example.com/?x=first&x=second&x=second&other=x")
        let rawSecond = range("second", in: app.left.string, occurrence: 1)
        let jsonSecond = range("\"second\"", in: app.right.string, occurrence: 1)
        select("\"second\"", in: app.right, occurrence: 1)
        app.updateLinkedSelection(from: .json, scroll: false)
        assertHighlights(app.left, [rawSecond])
        assertHighlights(app.right, [jsonSecond])

        select("second", in: app.left, occurrence: 0)
        app.updateLinkedSelection(from: .url, scroll: false)
        assertHighlights(app.left, [range("second", in: app.left.string)])
        assertHighlights(app.right, [range("\"second\"", in: app.right.string)])

        let key = range("\"x\"", in: app.right.string, occurrence: 1)
        app.right.setSelectedRange(NSRange(location: key.location + 1, length: 0))
        app.updateLinkedSelection(from: .json, scroll: false)
        let keys = (0..<3).map { occurrence -> NSRange in
            let pair = range("x=", in: app.left.string, occurrence: occurrence)
            return NSRange(location: pair.location, length: 1)
        }
        assertHighlights(app.left, keys)
        assertHighlights(app.right, [key])
    }

    func testWhitespaceAndEmojiUseUTF16OffsetsAndUnmappedTextClearsLinkage() {
        let app = makeEditor(" \t\nhttps://user:pass@example.com/😀?city=北😀京&next=%F0%9F%98%80#fragment \n")
        select("%F0%9F%98%80", in: app.left)
        app.updateLinkedSelection(from: .url, scroll: false)
        assertHighlights(app.left, [range("%F0%9F%98%80", in: app.left.string)])
        assertHighlights(app.right, [range("\"😀\"", in: app.right.string)])

        let city = range("北😀京", in: app.left.string)
        app.left.setSelectedRange(NSRange(location: city.location + 2, length: 0))
        app.updateLinkedSelection(from: .url, scroll: false)
        assertHighlights(app.left, [city])
        assertHighlights(app.right, [range("\"北😀京\"", in: app.right.string)])

        app.updateLinkedSelection(from: .component(2), scroll: false)
        assertHighlights(app.left, [range("/😀", in: app.left.string)])
        select("user", in: app.left)
        app.updateLinkedSelection(from: .url, scroll: false)
        assertNoLinkedHighlights(app)

        for offset in [0, (app.left.string as NSString).length - 1] {
            app.updateLinkedSelection(from: .component(0), scroll: false)
            app.left.setSelectedRange(NSRange(location: offset, length: 0))
            app.updateLinkedSelection(from: .url, scroll: false)
            assertNoLinkedHighlights(app)
        }
    }

    func testInvalidEditsAndClearRemoveStaleLinkage() {
        let app = makeEditor("https://example.com/path?key=original")
        select("\"original\"", in: app.right)
        app.updateLinkedSelection(from: .json, scroll: false)
        XCTAssertFalse(app.left.linkedHighlightRanges.isEmpty)
        edit(app) {
            app.right.string = "{"
            app.textDidChange(Notification(name: NSText.didChangeNotification, object: app.right))
        }
        assertNoLinkedHighlights(app)
        app.updateLinkedSelection(from: .json, scroll: false)
        assertNoLinkedHighlights(app)

        app.undoEdit()
        select("\"original\"", in: app.right)
        app.updateLinkedSelection(from: .json, scroll: false)
        assertHighlights(app.left, [range("original", in: app.left.string)])
        edit(app) {
            app.left.string = "not a URL"
            app.textDidChange(Notification(name: NSText.didChangeNotification, object: app.left))
        }
        assertNoLinkedHighlights(app)
        app.updateLinkedSelection(from: .component(0), scroll: false)
        assertNoLinkedHighlights(app)

        app.undoEdit()
        select("\"original\"", in: app.right)
        app.updateLinkedSelection(from: .json, scroll: false)
        edit(app) { app.clear() }
        assertNoLinkedHighlights(app)
        XCTAssertEqual(app.left.string, "")
        XCTAssertEqual(app.right.string, "{}")
    }

    func testEditUndoAndRedoRebuildCorrespondenceWithoutRecordingSelectionChanges() {
        let original = "https://old.example/?a=first"
        let changed = "https://new.example/longer/path?replacement=second"
        let app = makeEditor(original)
        edit(app) {
            app.left.string = changed
            app.textDidChange(Notification(name: NSText.didChangeNotification, object: app.left))
        }
        select("\"second\"", in: app.right)
        app.updateLinkedSelection(from: .json, scroll: false)
        assertHighlights(app.left, [range("second", in: changed)])

        app.undoEdit()
        XCTAssertEqual(app.left.string, original)
        select("\"first\"", in: app.right)
        app.updateLinkedSelection(from: .json, scroll: false)
        assertHighlights(app.left, [range("first", in: original)])
        XCTAssertFalse(app.history.canUndo)
        XCTAssertTrue(app.history.canRedo)

        app.redoEdit()
        XCTAssertEqual(app.left.string, changed)
        select("replacement", in: app.left)
        app.updateLinkedSelection(from: .url, scroll: false)
        assertHighlights(app.left, [range("replacement", in: changed)])
        assertHighlights(app.right, [range("\"replacement\"", in: app.right.string)])
        XCTAssertTrue(app.history.canUndo)
        XCTAssertFalse(app.history.canRedo)

        app.undoEdit()
        XCTAssertEqual(app.left.string, original)
        XCTAssertFalse(app.history.canUndo)
    }

    func testInsertionsAndDeletionsBeforeTheHighlightRemoveShiftedBackgrounds() {
        let app = makeEditor("https://user:pass@example.com/path?key=value#fragment")
        for (old, new) in [("/path", "/longer/😀/path"), ("example.com", "x.io")] {
            select("\"value\"", in: app.right)
            app.updateLinkedSelection(from: .json, scroll: false)
            XCTAssertFalse(app.left.linkedHighlightRanges.isEmpty)
            edit(app) {
                app.left.textStorage?.replaceCharacters(in: range(old, in: app.left.string), with: new)
                select("user", in: app.left)
                app.textDidChange(Notification(name: NSText.didChangeNotification, object: app.left))
            }
            assertNoLinkedHighlights(app)
        }

        select("\"value\"", in: app.right)
        app.updateLinkedSelection(from: .json, scroll: false)
        edit(app) {
            app.right.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 0), with: "\n   ")
            app.right.setSelectedRange(NSRange(location: 0, length: 0))
            app.textDidChange(Notification(name: NSText.didChangeNotification, object: app.right))
        }
        assertNoLinkedHighlights(app)
    }

    func testLinkedSelectionScrollsTheOtherEditorToItsTarget() {
        let query = (0..<400).map { String(format: "key%03d=value%03d", $0, $0) }.joined(separator: "&")
        let app = makeEditor("https://example.com/?" + query)
        let leftPane = app.pane("URL", app.left)
        let rightPane = app.pane("JSON", app.right)
        let root = NSStackView(views: [leftPane, rightPane])
        root.orientation = .horizontal
        root.distribution = .fillEqually
        for pane in [leftPane, rightPane] {
            pane.heightAnchor.constraint(equalTo: root.heightAnchor).isActive = true
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 280),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = root
        defer { window.close() }
        root.layoutSubtreeIfNeeded()

        select("value399", in: app.left)
        app.updateLinkedSelection(from: .url)
        let jsonTarget = range("\"value399\"", in: app.right.string)
        assertHighlights(app.right, [jsonTarget])
        assertVisible(jsonTarget, in: app.right)

        app.left.scrollRangeToVisible(NSRange(location: 0, length: 1))
        select("\"value399\"", in: app.right)
        app.updateLinkedSelection(from: .json)
        let urlTarget = range("value399", in: app.left.string)
        assertHighlights(app.left, [urlTarget])
        assertVisible(urlTarget, in: app.left)
    }

    private func assertVisible(_ range: NSRange, in view: NSTextView,
                               file: StaticString = #filePath, line: UInt = #line) {
        let layout = view.layoutManager!
        layout.ensureLayout(forCharacterRange: range)
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layout.boundingRect(forGlyphRange: glyphs, in: view.textContainer!)
        rect.origin.x += view.textContainerOrigin.x
        rect.origin.y += view.textContainerOrigin.y
        XCTAssertTrue(view.visibleRect.intersects(rect), "Linked target is outside the viewport", file: file, line: line)
    }
}
