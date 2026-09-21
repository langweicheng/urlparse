import AppKit
import URLCore

extension AppDelegate {
    func clearLinkedHighlights() {
        left.highlightLinkedRanges([])
        right.showLinkedSelection(nil)
        for field in componentFields where field.isLinkedHighlighted { field.isLinkedHighlighted = false }
    }

    func rebuildSourceIndex() {
        clearLinkedHighlights()
        // TextKit moves temporary attributes during edits; discard those shifted
        // ranges before building the new mapping.
        left.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: (left.string as NSString).length))
        indexedURL = left.string
        indexedJSON = right.string
        sourceIndex = document.map(URLSourceIndex.init)
        sourceOffset = document.map { (left.string as NSString).range(of: $0.original).location } ?? 0
    }

    func updateLinkedSelection(from source: SelectionSource, scroll: Bool = true) {
        guard !changing else { return }
        selectionSource = source
        // Selection notifications can arrive before the corresponding edit has
        // been parsed. Never apply offsets from the previous document to a draft.
        guard let sourceIndex, sourceOffset != NSNotFound,
              indexedURL == left.string, indexedJSON == right.string else {
            clearLinkedHighlights()
            return
        }
        let selection: URLSelection?
        let scrollURL: Bool
        let scrollJSON: Bool
        switch source {
        case .url:
            selection = sourceIndex.selection(at: (left.interactionPosition ?? left.selectedRange().location) - sourceOffset)
            scrollURL = false; scrollJSON = scroll
        case .json:
            selection = right.selection(at: right.interactionPosition ?? right.selectedRange().location)
            scrollURL = scroll; scrollJSON = false
        case .component(let index):
            guard componentFields.indices.contains(index) else { clearLinkedHighlights(); return }
            selection = .component(Self.components[index])
            scrollURL = scroll; scrollJSON = false
        }
        guard let selection else { clearLinkedHighlights(); return }
        switch selection {
        case .queryKey, .queryValue:
            guard canLinkQuery else { clearLinkedHighlights(); return }
        case .component: break
        }
        let ranges = sourceIndex.ranges(for: selection).map {
            NSRange(location: $0.location + sourceOffset, length: $0.length)
        }
        left.highlightLinkedRanges(ranges, scroll: scrollURL)
        right.showLinkedSelection(selection, scroll: scrollJSON)
        for (index, field) in componentFields.enumerated() {
            field.isLinkedHighlighted = selection == .component(Self.components[index])
        }
    }
}
