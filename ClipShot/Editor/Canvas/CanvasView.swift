import AppKit
import SwiftUI

struct CanvasView: NSViewRepresentable {
    @ObservedObject var state: EditorState

    func makeCoordinator() -> CanvasCoordinator { CanvasCoordinator() }

    func makeNSView(context: Context) -> CanvasScrollView {
        context.coordinator.update(state: state)
        return context.coordinator.scrollView
    }

    func updateNSView(_ nsView: CanvasScrollView, context: Context) {
        // SwiftUI re-invokes this whenever the observed EditorState changes
        // (e.g. document mutated). All on the main actor — safe to touch AppKit.
        context.coordinator.update(state: state)
    }
}
