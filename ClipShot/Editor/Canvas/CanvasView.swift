import AppKit
import SwiftUI

@MainActor
final class CanvasFocusProxy: ObservableObject {
    private weak var interactionView: CanvasInteractionView?

    func attach(_ interactionView: CanvasInteractionView) {
        self.interactionView = interactionView
    }

    func requestKeyboardFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let interactionView = self?.interactionView else { return }
            interactionView.requestKeyboardFocus()
        }
    }
}

struct CanvasView: NSViewRepresentable {
    @ObservedObject var state: EditorState
    @ObservedObject var focusProxy: CanvasFocusProxy

    func makeCoordinator() -> CanvasCoordinator { CanvasCoordinator() }

    func makeNSView(context: Context) -> CanvasScrollView {
        focusProxy.attach(context.coordinator.interactionView)
        context.coordinator.update(state: state)
        return context.coordinator.scrollView
    }

    func updateNSView(_ nsView: CanvasScrollView, context: Context) {
        // SwiftUI re-invokes this whenever the observed EditorState changes
        // (e.g. document mutated). All on the main actor — safe to touch AppKit.
        focusProxy.attach(context.coordinator.interactionView)
        context.coordinator.update(state: state)
    }
}
