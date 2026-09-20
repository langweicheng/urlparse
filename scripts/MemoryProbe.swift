#if MEMORY_PROBE
import AppKit
import Darwin

// Compile-time-only benchmark: identical workload for before/after builds.
enum MemoryProbe {
    static func start(_ app: AppDelegate) {
        let query = (0..<1000).map { "key\($0)=value%20\($0)" }.joined(separator: "&")
        let steps: [(String, () -> Void)] = [
            ("empty", {}),
            ("1000_parameters", {
                app.left.string = "imeituan://host/mrn?" + query
                app.textDidChange(Notification(name: NSText.didChangeNotification, object: app.left))
            }),
            ("100_edits", {
                for _ in 0..<100 {
                    autoreleasepool {
                        app.left.string += "x"
                        app.textDidChange(Notification(name: NSText.didChangeNotification, object: app.left))
                    }
                }
            }),
            ("qr_open", {
                app.left.string = "https://example.com/?city=%E5%8C%97%E4%BA%AC"
                app.textDidChange(Notification(name: NSText.didChangeNotification, object: app.left))
                app.showQR()
            }),
            ("qr_closed", { app.qrWindow?.close() })
        ]
        func run(_ index: Int) {
            guard index < steps.count else { NSApp.terminate(nil); return }
            steps[index].1()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                var info = task_vm_info_data_t()
                var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
                let result = withUnsafeMutablePointer(to: &info) { pointer in
                    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                    }
                }
                if result == KERN_SUCCESS {
                    print("LAYOUT frame=\(app.right.frame) max=\(app.right.maxSize) container=\(String(describing: app.right.textContainer?.containerSize))")
                    print("MEMORY \(steps[index].0) rss=\(info.resident_size) footprint=\(info.phys_footprint)")
                    fflush(stdout)
                }
                run(index + 1)
            }
        }
        run(0)
    }
}
#endif
