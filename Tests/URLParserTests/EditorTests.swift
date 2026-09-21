import XCTest
import AppKit
@testable import URLParser

final class EditorTests: XCTestCase {
    func testComponentEditsSynchronizeAndUndoIncludingInvalidDrafts() throws {
        _ = NSApplication.shared
        let editor = AppDelegate()
        editor.history.groupsByEvent = false
        func edit(_ action: () -> Void) {
            editor.history.beginUndoGrouping()
            action()
            editor.history.endUndoGrouping()
        }
        edit {
            editor.left.string = "https://old.example:443/path?keep=%2f#frag"
            editor.textDidChange(Notification(name: NSText.didChangeNotification, object: editor.left))
        }
        let originalJSON = editor.right.string
        XCTAssertEqual(editor.hostField.stringValue, "old.example")
        edit {
            editor.hostField.stringValue = "new.example"
            editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: editor.hostField))
        }
        XCTAssertEqual(editor.left.string, "https://new.example:443/path?keep=%2f#frag")
        XCTAssertEqual(editor.right.string, originalJSON)
        editor.undoEdit()
        XCTAssertEqual(editor.hostField.stringValue, "old.example")
        XCTAssertTrue(editor.left.string.contains("old.example"))
        editor.redoEdit()
        XCTAssertEqual(editor.hostField.stringValue, "new.example")
        let validURL = editor.left.string
        edit {
            editor.schemeField.stringValue = ""
            editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: editor.schemeField))
        }
        XCTAssertEqual(editor.left.string, validURL)
        XCTAssertTrue(editor.status.stringValue.hasPrefix("未同步"))
        editor.undoEdit()
        XCTAssertEqual(editor.schemeField.stringValue, "https")
        editor.redoEdit()
        XCTAssertEqual(editor.schemeField.stringValue, "")
        XCTAssertEqual(editor.left.string, validURL)
        XCTAssertTrue(editor.status.stringValue.hasPrefix("未同步"))
        edit {
            editor.schemeField.stringValue = "custom"
            editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: editor.schemeField))
        }
        edit {
            editor.pathField.stringValue = "/new path"
            editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: editor.pathField))
        }
        XCTAssertEqual(editor.left.string, "custom://new.example:443/new%20path?keep=%2f#frag")
        edit {
            editor.right.string = "{\"keep\":\"changed\"}"
            editor.textDidChange(Notification(name: NSText.didChangeNotification, object: editor.right))
        }
        XCTAssertEqual(editor.left.string, "custom://new.example:443/new%20path?keep=changed#frag")
        XCTAssertEqual(editor.pathField.stringValue, "/new%20path")
    }

    func testCreateURLFromEmptyFieldsInAnyOrder() throws {
        _ = NSApplication.shared
        for order in [[0, 1, 2], [1, 2, 0], [2, 0, 1]] {
            let editor = AppDelegate()
            editor.history.groupsByEvent = false
            let values = ["https", "example.com", "/中文 path"]
            for index in order {
                XCTAssertTrue(editor.componentFields[index].isEnabled)
                editor.history.beginUndoGrouping()
                editor.componentFields[index].stringValue = values[index]
                editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: editor.componentFields[index]))
                editor.history.endUndoGrouping()
            }
            XCTAssertEqual(editor.left.string, "https://example.com/%E4%B8%AD%E6%96%87%20path")
            XCTAssertNotNil(editor.document)
            editor.undoEdit()
            editor.redoEdit()
            XCTAssertEqual(editor.left.string, "https://example.com/%E4%B8%AD%E6%96%87%20path")
            XCTAssertEqual(editor.componentFields.map(\.stringValue), values + [""])
            for _ in 0..<3 { editor.undoEdit() }
            XCTAssertEqual(editor.left.string, "")
            XCTAssertEqual(editor.componentFields.map(\.stringValue), ["", "", "", ""])
            XCTAssertTrue(editor.componentFields.allSatisfy(\.isEnabled))
        }
    }

    func testDraftSurvivesJSONEditingBeforeSchemeAndClear() {
        _ = NSApplication.shared
        let editor = AppDelegate()
        editor.hostField.stringValue = "example.com"
        editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: editor.hostField))
        editor.right.string = "{\"a\":\"1\"}"
        editor.textDidChange(Notification(name: NSText.didChangeNotification, object: editor.right))
        XCTAssertEqual(editor.hostField.stringValue, "example.com")
        editor.schemeField.stringValue = "https"
        editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: editor.schemeField))
        XCTAssertEqual(editor.left.string, "https://example.com?a=1")
        editor.clear()
        XCTAssertEqual(editor.componentFields.map(\.stringValue), ["", "", "", ""])
        XCTAssertTrue(editor.componentFields.allSatisfy(\.isEnabled))
    }

    func testIncrementalSyntaxMatchesFullHighlight() {
        let view = JSONTextView()
        let texts = [
            #"{"a":"one","b":"two","c":null}"#,
            #"{"a":"ONE","b":"two","c":null}"#,
            #"{"a":"ONE x","b":"two","c":null}"#,
            #"{"a":"ONE x","b":12,"c":null}"#,
            #"{"a":"ONE x","b":true,"c":null}"#,
            #"{"a":"ONE x","b":"two","c":null}"#,
            #"{"b":"two","c":null}"#,
            #"{"b":"two","c":null,"d":["中文","😀"]}"#,
            #"{"b":"two","c":null,"d":["中文","😀"]"#,
            "{", "", "{}", #"{"b":"two"}"#
        ]
        for text in texts {
            view.replaceContent(with: text)
            view.refreshSyntax()
            let reference = JSONTextView()
            reference.string = text
            reference.refreshSyntax()
            for position in 0..<(text as NSString).length {
                let actual = view.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: position, effectiveRange: nil) as? NSColor
                let expected = reference.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: position, effectiveRange: nil) as? NSColor
                XCTAssertEqual(actual, expected, "position \(position) in \(text)")
            }
        }
        // Direct user edits, including replacement without a length change.
        view.textStorage?.replaceCharacters(in: NSRange(location: 6, length: 3), with: "NEW")
        view.refreshSyntax()
        XCTAssertNotNil(view.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 7, effectiveRange: nil))
    }

    func testLazyLayoutCanScrollToLastLineAndBack() {
        _ = NSApplication.shared
        let app = AppDelegate()
        let pane = app.pane("JSON", app.right)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = pane
        pane.layoutSubtreeIfNeeded()
        app.right.string = "{\n" + (0..<1000).map { "\"key\($0)\":\"value\($0)\"" }.joined(separator: ",\n") + "\n}"
        app.right.refreshSyntax()
        let layout = app.right.layoutManager!
        XCTAssertTrue(layout.allowsNonContiguousLayout)
        for offset in [(app.right.string as NSString).length - 2, 0] {
            let range = NSRange(location: offset, length: 1)
            app.right.scrollRangeToVisible(range)
            layout.ensureLayout(forCharacterRange: range)
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layout.boundingRect(forGlyphRange: glyphs, in: app.right.textContainer!)
            rect.origin.x += app.right.textContainerOrigin.x
            rect.origin.y += app.right.textContainerOrigin.y
            XCTAssertTrue(app.right.visibleRect.intersects(rect), "Could not scroll to \(offset)")
        }
        window.close()
    }

    func testSplitDefaultsAndRestoresRatio() {
        let name = "URLParserTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        defer { preferences.removePersistentDomain(forName: name) }
        func makeSplit(width: CGFloat) -> PersistentSplitView {
            let split = PersistentSplitView(frame: NSRect(x: 0, y: 0, width: width, height: 600), preferences: preferences)
            split.isVertical = true
            split.addArrangedSubview(NSView(frame: NSRect(x: 0, y: 0, width: width / 2, height: 600)))
            split.addArrangedSubview(NSView(frame: NSRect(x: width / 2, y: 0, width: width / 2, height: 600)))
            split.adjustSubviews()
            split.restorePosition()
            split.layoutSubtreeIfNeeded()
            return split
        }
        let split = makeSplit(width: 1000)
        XCTAssertEqual(split.subviews[0].frame.width / (split.bounds.width - split.dividerThickness), 0.5, accuracy: 0.002)
        split.setPosition((split.bounds.width - split.dividerThickness) * 0.65, ofDividerAt: 0)
        split.layoutSubtreeIfNeeded()
        split.savePosition()
        let reopened = makeSplit(width: 1200)
        XCTAssertEqual(reopened.subviews[0].frame.width / (reopened.bounds.width - reopened.dividerThickness), 0.65, accuracy: 0.002)
    }

    func testContextMenuDistinguishesKeyAndValue() throws {
        _ = NSApplication.shared
        for (character, expectedTitle, expectedText) in [
            (2, "删除 Key（整个参数）", "{\"other\":\"x\"}"),
            (9, "删除 Value（清空值）", "{\"city\":\"\",\"other\":\"x\"}"),
            (9, "删除整个参数", "{\"other\":\"x\"}")
        ] {
            let view = JSONTextView()
            view.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
            view.string = "{\"city\":\"北京\",\"other\":\"x\"}"
            view.refreshSyntax()
            let layout = view.layoutManager!
            layout.ensureLayout(for: view.textContainer!)
            let glyph = layout.glyphIndexForCharacter(at: character)
            let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: view.textContainer!)
            let point = view.convert(NSPoint(x: rect.midX + view.textContainerOrigin.x, y: rect.midY + view.textContainerOrigin.y), to: nil)
            if character == 2 {
                let click = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                view.mouseDown(with: click)
                XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "city")
            }
            let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            let menu = try XCTUnwrap(view.menu(for: event))
            XCTAssertFalse(menu.allowsContextMenuPlugIns)
            XCTAssertEqual(menu.items.count, character == 2 ? 2 : 3)
            let item = try XCTUnwrap(menu.items.first { $0.title == expectedTitle })
            _ = (item.target as? NSObject)?.perform(item.action)
            XCTAssertEqual(view.string, expectedText)
        }
    }

    func testSyntaxAndPairHighlightDoNotModifyText() {
        let view = JSONTextView()
        view.string = #"{"city":"北京","flag":null}"#
        let original = view.string
        view.refreshSyntax()
        view.setSelectedRange(NSRange(location: 2, length: 4))
        view.refreshSelectionHighlight()
        let layout = view.layoutManager!
        let keyColor = layout.temporaryAttribute(.foregroundColor, atCharacterIndex: 2, effectiveRange: nil) as? NSColor
        let valueColor = layout.temporaryAttribute(.foregroundColor, atCharacterIndex: 9, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(keyColor); XCTAssertNotNil(valueColor)
        XCTAssertNotEqual(keyColor, valueColor)
        XCTAssertNotNil(layout.temporaryAttribute(.backgroundColor, atCharacterIndex: 2, effectiveRange: nil))
        XCTAssertNotNil(layout.temporaryAttribute(.backgroundColor, atCharacterIndex: 9, effectiveRange: nil))
        XCTAssertNil(layout.temporaryAttribute(.backgroundColor, atCharacterIndex: 15, effectiveRange: nil))
        XCTAssertEqual(view.string, original)
        // An unfinished edit must not leave stale ranges that crash highlighting.
        view.string = "{"
        view.refreshSelectionHighlight()
        view.refreshSyntax()
        XCTAssertEqual(view.string, "{")
    }
}
