import AppKit
import URLCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextViewDelegate, NSTextFieldDelegate {
    var window: NSWindow!
    let left = AppDelegate.makeEditor()
    let right = JSONTextView()
    static func makeEditor() -> NSTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = true
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        return NSTextView(frame: .zero, textContainer: container)
    }
    let schemeField = NSTextField(string: "")
    let hostField = NSTextField(string: "")
    let pathField = NSTextField(string: "")
    var componentFields: [NSTextField] { [schemeField, hostField, pathField] }
    let status = NSTextField(wrappingLabelWithString: "粘贴 URL，或填写协议、Host 和路径创建 URL。")
    let history = UndoManager()
    var document: URLDocument?
    var changing = false
    struct State { let url: String; let json: String; var components: [String] = ["", "", ""] }
    var state = State(url: "", json: "{}")
    var qrWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        history.levelsOfUndo = 100
        makeMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "URL Parser"
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 720, height: 440)
        window.delegate = self
        window.setFrameAutosaveName("MainWindow")
        let root = NSStackView()
        root.orientation = .vertical; root.spacing = 0
        root.edgeInsets = NSEdgeInsetsZero
        let body = NSStackView()
        body.orientation = .vertical; body.spacing = 12
        body.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12)
        let bar = NSStackView(views: [button("粘贴 URL", #selector(pasteURL)), button("复制 URL", #selector(copyURL)), button("复制 JSON", #selector(copyJSON)), button("清空", #selector(clear)), button("撤销", #selector(undoEdit)), button("重做", #selector(redoEdit)), button("生成二维码", #selector(showQR))])
        bar.spacing = 8
        // Full-width toolbar: padding belongs inside it, including the space
        // reserved for the native window controls on the left.
        bar.edgeInsets = NSEdgeInsets(top: 4, left: 80, bottom: 4, right: 8)
        root.addArrangedSubview(bar)
        root.addArrangedSubview(body)
        let split = PersistentSplitView(frame: .zero)
        split.isVertical = true; split.dividerStyle = .thin
        split.addArrangedSubview(pane("URL", left))
        split.addArrangedSubview(pane("Query JSON · 可编辑", right))
        let fields = NSStackView()
        fields.spacing = 8
        for (title, field) in zip(["协议", "Host", "路径"], componentFields) {
            field.delegate = self
            field.placeholderString = title
            field.setAccessibilityLabel(title)
            field.bezelStyle = .squareBezel
            field.focusRingType = .none
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            fields.addArrangedSubview(NSTextField(labelWithString: title))
            fields.addArrangedSubview(field)
        }
        schemeField.widthAnchor.constraint(equalToConstant: 90).isActive = true
        hostField.widthAnchor.constraint(equalTo: pathField.widthAnchor, multiplier: 0.7).isActive = true
        body.addArrangedSubview(fields)
        body.addArrangedSubview(split)
        body.addArrangedSubview(status)
        status.font = .systemFont(ofSize: 12)
        window.contentView = root
        for v in [bar, body] { v.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        for v in [split, fields, status] { v.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -24).isActive = true }
        bar.heightAnchor.constraint(equalToConstant: 36).isActive = true
        window.minSize.width = max(720, bar.fittingSize.width)
        split.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        right.string = "{}"
        right.refreshSyntax()
        window.center(); window.makeKeyAndOrderFront(nil)
        root.layoutSubtreeIfNeeded()
        split.restorePosition()
        window.makeFirstResponder(left)
        NSApp.activate(ignoringOtherApps: true)
    }

    func button(_ title: String, _ action: Selector) -> NSButton {
        let button = FlatButton(title: title, target: self, action: action)
        button.cell = PaddedButtonCell(textCell: title)
        button.target = self; button.action = action
        button.setButtonType(.momentaryPushIn)
        button.isBordered = false
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.contentTintColor = .labelColor
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let symbols = ["粘贴 URL": "doc.on.clipboard", "复制 URL": "link", "复制 JSON": "curlybraces", "清空": "trash", "撤销": "arrow.uturn.backward", "重做": "arrow.uturn.forward", "生成二维码": "qrcode"]
        if let symbol = symbols[title] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            button.imagePosition = .imageLeading
        }
        return button
    }
    func pane(_ title: String, _ editor: NSTextView) -> NSView {
        editor.isRichText = false; editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false; editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false; editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.isAutomaticTextCompletionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        if #available(macOS 14.0, *) { editor.inlinePredictionType = .no }
        if #available(macOS 15.0, *) { editor.writingToolsBehavior = .none }
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        editor.delegate = self; editor.allowsUndo = false
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .lineBorder
        // Keep backing storage viewport-sized instead of allocating a layer for the entire document.
        scroll.wantsLayer = true
        scroll.canDrawSubviewsIntoLayer = true
        editor.wantsLayer = false
        scroll.documentView = editor
        let stack = NSStackView(views: [NSTextField(labelWithString: title), scroll])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        return stack
    }

    func makeMenu() {
        let menu = NSMenu()
        let app = NSMenuItem(); menu.addItem(app); app.submenu = NSMenu()
        app.submenu?.addItem(withTitle: "退出 URL Parser", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); edit.title = "编辑"; edit.submenu = NSMenu(title: "编辑"); menu.addItem(edit)
        let undo = edit.submenu!.addItem(withTitle: "撤销", action: #selector(undoEdit), keyEquivalent: "z"); undo.target = self
        let redo = edit.submenu!.addItem(withTitle: "重做", action: #selector(redoEdit), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]; redo.target = self
        edit.submenu?.addItem(.separator())
        for (title, selector, key) in [("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.submenu?.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        NSApp.mainMenu = menu
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !changing, (notification.object as? NSTextView) === right else { return }
        right.refreshSelectionHighlight()
    }
    func textDidChange(_ notification: Notification) {
        guard !changing else { return }
        let previous = state
        synchronize(fromLeft: (notification.object as? NSTextView) === left)
        right.refreshSyntax()
        recordEdit(previous: previous)
    }
    func recordEdit(previous: State) {
        state = State(url: left.string, json: right.string, components: componentFields.map(\.stringValue))
        let componentPatches = zip(previous.components, state.components).map { TextPatch(from: $0.0, to: $0.1) }
        let urlPatch = TextPatch(from: previous.url, to: state.url)
        let jsonPatch = TextPatch(from: previous.json, to: state.json)
        history.registerUndo(withTarget: self) { $0.restore(urlPatch: urlPatch, jsonPatch: jsonPatch, componentPatches: componentPatches, reversed: true) }
        history.setActionName("编辑")
    }
    func restore(urlPatch: TextPatch, jsonPatch: TextPatch, componentPatches: [TextPatch], reversed: Bool) {
        history.registerUndo(withTarget: self) { $0.restore(urlPatch: urlPatch, jsonPatch: jsonPatch, componentPatches: componentPatches, reversed: !reversed) }
        let restored = State(url: urlPatch.apply(to: state.url, reversed: reversed), json: jsonPatch.apply(to: state.json, reversed: reversed), components: zip(componentPatches, state.components).map { $0.0.apply(to: $0.1, reversed: reversed) })
        changing = true; left.replaceContent(with: restored.url); right.replaceContent(with: restored.json); changing = false
        state = restored; document = try? URLDocument(restored.url)
        right.refreshSyntax()
        for (field, value) in zip(componentFields, restored.components) { field.stringValue = value }
        updateStatus(validate: true)
        validateComponentDrafts()
    }
    func refreshComponents() {
        let values = document.map { [$0.scheme, $0.host, $0.path] } ?? ["", "", ""]
        for (field, value) in zip(componentFields, values) { field.stringValue = value }
    }
    func controlTextDidBeginEditing(_ notification: Notification) {
        ((notification.object as? NSTextField)?.currentEditor() as? NSTextView)?.allowsUndo = false
    }
    func controlTextDidChange(_ notification: Notification) {
        guard !changing, let field = notification.object as? NSTextField,
              let index = componentFields.firstIndex(where: { $0 === field }) else { return }
        let previous = state
        do {
            let component: URLDocument.Component = [.scheme, .host, .path][index]
            let url: String
            if let document {
                url = try document.applying(component: component, value: field.stringValue)
            } else {
                var draft = try URLDocument("https://")
                for (part, input) in zip([URLDocument.Component.scheme, .host, .path], componentFields) {
                    draft = try URLDocument(draft.applying(component: part, value: input.stringValue))
                }
                // Keep unfinished JSON visible while creating a URL from the fields.
                url = (try? draft.applying(json: right.string)) ?? draft.original
            }
            self.document = try URLDocument(url)
            changing = true; left.replaceContent(with: url); changing = false
            updateStatus(validate: true)
            validateComponentDrafts()
        } catch {
            status.textColor = .systemRed; status.stringValue = "未同步：" + error.localizedDescription
        }
        recordEdit(previous: previous)
    }
    func validateComponentDrafts() {
        guard let document else {
            if componentFields.contains(where: { !$0.stringValue.isEmpty }) {
                status.textColor = .systemRed
                status.stringValue = "未同步：请填写有效协议，例如 https；Host 和路径可先填写。"
            }
            return
        }
        do {
            for (component, field) in zip([URLDocument.Component.scheme, .host, .path], componentFields) {
                // Host is absent in opaque URLs such as mailto:; leave it alone.
                if component == .host && field.stringValue == document.host { continue }
                _ = try document.applying(component: component, value: field.stringValue)
            }
        } catch {
            status.textColor = .systemRed; status.stringValue = "未同步：" + error.localizedDescription
        }
    }
    func synchronize(fromLeft: Bool) {
        changing = true
        var shouldRefreshComponents = fromLeft
        defer { if shouldRefreshComponents { refreshComponents() }; changing = false }
        do {
            if fromLeft {
                if left.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    document = nil; right.replaceContent(with: "{}"); status.stringValue = "请输入 URL"; return
                }
                let parsed = try URLDocument(left.string)
                document = parsed; right.replaceContent(with: parsed.json)
            } else {
                guard let document else { throw Failure("请先在左侧输入有效 URL") }
                let url = try document.applying(json: right.string)
                left.replaceContent(with: url); self.document = try URLDocument(url)
                shouldRefreshComponents = true
            }
            updateStatus()
        } catch {
            if fromLeft { document = nil }
            status.textColor = .systemRed; status.stringValue = "未同步：" + error.localizedDescription
        }
    }
    func updateStatus(validate: Bool = false) {
        status.textColor = .secondaryLabelColor
        status.stringValue = "已同步"
        status.toolTip = "重复参数用数组；null 表示无等号参数；+ 按字面保留；百分号解码一层。"
        if let document {
            if validate {
                do { _ = try document.applying(json: right.string) }
                catch { status.textColor = .systemRed; status.stringValue = "未同步：" + error.localizedDescription }
            }
        } else { status.stringValue = left.string.isEmpty ? "请输入 URL" : "URL 无效，未同步" }
    }
    @objc func undoEdit() { history.undo() }
    @objc func redoEdit() { history.redo() }
    @objc func pasteURL() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        left.string = text; textDidChange(Notification(name: NSText.didChangeNotification, object: left))
    }
    func copy(_ string: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(string, forType: .string) }
    @objc func copyURL() { copy(left.string) }
    @objc func copyJSON() { copy(right.string) }
    @objc func clear() { left.string = ""; textDidChange(Notification(name: NSText.didChangeNotification, object: left)) }

    @objc func showQR() {
        let text = left.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let cg: CGImage
        do { cg = try QRCode.image(for: text) }
        catch { status.textColor = .systemRed; status.stringValue = error.localizedDescription; return }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        let view = NSImageView(); view.image = image; view.imageScaling = .scaleNone
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 480), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.delegate = self
        panel.isReleasedWhenClosed = false; panel.title = "当前 URL 二维码（\(text.utf8.count) 字节）"
        panel.contentView = view; qrWindow?.close(); qrWindow = panel
        panel.center(); panel.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === qrWindow else { return }
        closing.contentView = nil
        qrWindow = nil
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
