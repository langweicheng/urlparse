import XCTest
import AppKit
@testable import URLParser

final class HashTests: XCTestCase {
    private func makeEditor(_ url: String = "") -> AppDelegate {
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

    private func editHash(_ value: String, in app: AppDelegate) {
        edit(app) {
            app.hashField.stringValue = value
            app.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: app.hashField))
        }
    }

    func testHashDisplaysRawFragmentWithoutAddingItsParametersToQueryJSON() throws {
        let hash = "#/酒店😀?tab=detail&token=%2f"
        let app = makeEditor("https://example.com/path?keep=%2f" + hash)
        XCTAssertEqual(app.hashField.stringValue, hash)
        XCTAssertEqual(app.document?.hash, hash)
        XCTAssertEqual(app.pathField.stringValue, "/path")
        let query = try JSONSerialization.jsonObject(with: Data(app.right.string.utf8)) as? [String: String]
        XCTAssertEqual(query, ["keep": "/"])

        edit(app) {
            app.right.string = #"{"keep":"changed"}"#
            app.textDidChange(Notification(name: NSText.didChangeNotification, object: app.right))
        }
        XCTAssertEqual(app.left.string, "https://example.com/path?keep=changed" + hash)
        XCTAssertEqual(app.hashField.stringValue, hash)
        XCTAssertEqual(app.document?.hash, hash)
    }

    func testHashEditsAcceptOptionalMarkerAndSupportUndoRedoAndRemoval() {
        let prefix = "https://user:pass@example.com:8443/a%20b?keep=%2f"
        let app = makeEditor(prefix + "#old")
        let originalJSON = app.right.string

        editHash("section", in: app)
        XCTAssertEqual(app.left.string, prefix + "#section")
        XCTAssertEqual(app.document?.hash, "#section")
        XCTAssertEqual(app.hashField.stringValue, "section")
        XCTAssertEqual(app.right.string, originalJSON)

        let route = "#/route?mode=compact&tab=info"
        editHash(route, in: app)
        XCTAssertEqual(app.left.string, prefix + route)
        XCTAssertEqual(app.hashField.stringValue, route)
        XCTAssertEqual(app.right.string, originalJSON)
        app.undoEdit()
        XCTAssertEqual(app.left.string, prefix + "#section")
        XCTAssertEqual(app.hashField.stringValue, "section")
        app.redoEdit()
        XCTAssertEqual(app.left.string, prefix + route)
        XCTAssertEqual(app.hashField.stringValue, route)

        editHash("", in: app)
        XCTAssertEqual(app.left.string, prefix)
        XCTAssertEqual(app.document?.hash, "")
        XCTAssertEqual(app.right.string, originalJSON)
        app.undoEdit()
        XCTAssertEqual(app.left.string, prefix + route)
        XCTAssertEqual(app.hashField.stringValue, route)
        app.redoEdit()
        XCTAssertEqual(app.left.string, prefix)
        XCTAssertEqual(app.hashField.stringValue, "")
        XCTAssertEqual(app.right.string, originalJSON)
    }

    func testEmptyHashIsDistinctFromNoHashAndClearRestoresWithUndo() {
        let url = "https://example.com/path?key=value"
        let app = makeEditor(url)
        XCTAssertEqual(app.hashField.stringValue, "")
        XCTAssertEqual(app.document?.hash, "")

        editHash("#", in: app)
        XCTAssertEqual(app.left.string, url + "#")
        XCTAssertEqual(app.hashField.stringValue, "#")
        XCTAssertEqual(app.document?.hash, "#")
        edit(app) { app.clear() }
        XCTAssertEqual(app.left.string, "")
        XCTAssertEqual(app.right.string, "{}")
        XCTAssertEqual(app.componentFields.map(\.stringValue), ["", "", "", ""])
        XCTAssertNil(app.document)
        app.undoEdit()
        XCTAssertEqual(app.left.string, url + "#")
        XCTAssertEqual(app.hashField.stringValue, "#")
        app.redoEdit()
        XCTAssertEqual(app.hashField.stringValue, "")
        XCTAssertEqual(app.left.string, "")
    }

    func testHashDraftBeforeSchemeSurvivesQueryEditingAndCreatesURL() {
        let app = makeEditor()
        let hash = "#/route?tab=details&encoded=%2f"
        editHash(hash, in: app)
        XCTAssertEqual(app.left.string, "")
        XCTAssertEqual(app.hashField.stringValue, hash)
        edit(app) {
            app.right.string = #"{"q":"one"}"#
            app.textDidChange(Notification(name: NSText.didChangeNotification, object: app.right))
        }
        XCTAssertEqual(app.hashField.stringValue, hash)
        edit(app) {
            app.hostField.stringValue = "example.com"
            app.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: app.hostField))
        }
        edit(app) {
            app.schemeField.stringValue = "https"
            app.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: app.schemeField))
        }
        let url = "https://example.com?q=one" + hash
        XCTAssertEqual(app.left.string, url)
        XCTAssertEqual(app.document?.hash, hash)
        XCTAssertEqual(app.hashField.stringValue, hash)
        XCTAssertEqual(app.status.stringValue, "已同步")
        app.undoEdit()
        XCTAssertEqual(app.left.string, "")
        XCTAssertEqual(app.schemeField.stringValue, "")
        XCTAssertEqual(app.hashField.stringValue, hash)
        app.redoEdit()
        XCTAssertEqual(app.left.string, url)
        XCTAssertEqual(app.hashField.stringValue, hash)
    }

    func testInvalidHashDraftDoesNotChangeURLAndCanBeUndoneAndRedone() {
        let url = "https://example.com/path?key=value#old"
        let app = makeEditor(url)
        let originalJSON = app.right.string
        editHash("#bad%GG", in: app)
        XCTAssertEqual(app.left.string, url)
        XCTAssertEqual(app.right.string, originalJSON)
        XCTAssertEqual(app.document?.hash, "#old")
        XCTAssertEqual(app.hashField.stringValue, "#bad%GG")
        XCTAssertTrue(app.status.stringValue.hasPrefix("未同步"))
        app.undoEdit()
        XCTAssertEqual(app.left.string, url)
        XCTAssertEqual(app.hashField.stringValue, "#old")
        XCTAssertEqual(app.status.stringValue, "已同步")
        app.redoEdit()
        XCTAssertEqual(app.left.string, url)
        XCTAssertEqual(app.hashField.stringValue, "#bad%GG")
        XCTAssertTrue(app.status.stringValue.hasPrefix("未同步"))
    }
}
