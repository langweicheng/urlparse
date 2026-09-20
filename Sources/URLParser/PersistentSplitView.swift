import AppKit

final class PersistentSplitView: NSSplitView {
    private let preferences: UserDefaults
    private let preferenceKey = "editorSplitRatio"
    private var dragging = false
    private var restoring = false
    private var ratio: CGFloat = 0.5

    init(frame frameRect: NSRect, preferences: UserDefaults = .standard) {
        self.preferences = preferences
        super.init(frame: frameRect)
        let saved = preferences.double(forKey: preferenceKey)
        if saved > 0, saved < 1 { ratio = saved }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func restorePosition() {
        guard !dragging, !restoring, subviews.count == 2, bounds.width > 0 else { return }
        restoring = true
        setPosition((bounds.width - dividerThickness) * ratio, ofDividerAt: 0)
        restoring = false
    }
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        restorePosition()
    }
    override func mouseDown(with event: NSEvent) {
        dragging = true
        super.mouseDown(with: event)
        dragging = false
        savePosition()
    }
    func savePosition() {
        let width = bounds.width - dividerThickness
        if width > 0, let first = subviews.first {
            ratio = first.frame.width / width
            preferences.set(Double(ratio), forKey: preferenceKey)
        }
    }
}
