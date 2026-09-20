#if PERFORMANCE_PROBE
import AppKit

enum PerformanceProbe {
    static func start(_ app: AppDelegate) {
        DispatchQueue.main.async {
            let query = (0..<1000).map { "key\($0)=value%20\($0)" }.joined(separator: "&")
            app.left.string = "custom://example.com/path?" + query
            app.textDidChange(Notification(name: NSText.didChangeNotification, object: app.left))
            func draw() {
                for editor in [app.left, app.right] {
                    if let container = editor.textContainer {
                        editor.layoutManager?.ensureLayout(forBoundingRect: editor.visibleRect, in: container)
                    }
                }
                app.window.displayIfNeeded()
            }
            draw()
            var phases: [String: Double] = [:]
            func phase(_ name: String, _ work: () -> Void) {
                let start = CFAbsoluteTimeGetCurrent(); work()
                phases[name, default: 0] += (CFAbsoluteTimeGetCurrent() - start) * 1000
            }
            func change(fromLeft: Bool) {
                let previous = app.state
                phase("synchronize") { app.synchronize(fromLeft: fromLeft) }
                phase("highlight") { app.right.refreshSyntax() }
                phase("undo_record") { app.recordEdit(previous: previous) }
            }
            func measure(_ name: String, _ change: () -> Void) {
                phases = [:]
                var samples: [Double] = []
                for _ in 0..<30 {
                    autoreleasepool {
                        let start = CFAbsoluteTimeGetCurrent()
                        change(); phase("draw") { draw() }
                        samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
                    }
                }
                samples.sort()
                print(String(format: "%@ mean_ms=%.2f p95_ms=%.2f", name, samples.reduce(0,+) / Double(samples.count), samples[28]))
                for key in phases.keys.sorted() { print(String(format: "  %@ mean_ms=%.2f", key, phases[key]! / 30)) }
            }
            measure("URL_edit_1000_parameters") {
                app.left.textStorage?.append(NSAttributedString(string: "x"))
                change(fromLeft: true)
            }
            measure("JSON_edit_1000_parameters") {
                let text = app.right.string as NSString
                let range = text.range(of: "value")
                app.right.textStorage?.replaceCharacters(in: NSRange(location: range.location, length: 0), with: "x")
                change(fromLeft: false)
            }
            NSApp.terminate(nil)
        }
    }
}
#endif
