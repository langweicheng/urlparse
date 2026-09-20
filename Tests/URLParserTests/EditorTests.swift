import XCTest
import AppKit
@testable import URLParser

final class EditorTests: XCTestCase {
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
            (9, "删除 Value（清空值）", "{\"city\":\"\",\"other\":\"x\"}")
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
