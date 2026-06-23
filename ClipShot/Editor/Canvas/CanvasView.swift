import AppKit
import SwiftUI

@MainActor
final class CanvasFocusProxy: ObservableObject {
    private weak var interactionView: CanvasInteractionView?
    private weak var state: EditorState?
    private let keyMonitor = CanvasKeyMonitor()

    func attach(_ interactionView: CanvasInteractionView, state: EditorState) {
        self.interactionView = interactionView
        self.state = state
        installKeyMonitorIfNeeded()
    }

    func requestKeyboardFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let interactionView = self?.interactionView else { return }
            interactionView.requestKeyboardFocus()
        }
    }

    private func installKeyMonitorIfNeeded() {
        keyMonitor.install { [weak self] event in
            let didHandle = MainActor.assumeIsolated {
                self?.handleKeyDown(event) ?? false
            }
            return didHandle ? nil : event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let state,
              let interactionView,
              let window = interactionView.window,
              event.window === window,
              window.isKeyWindow,
              !window.firstResponderAcceptsTextInput,
              !state.previewingOriginal,
              state.activeTool == .select,
              state.selectedAnnotationID != nil,
              let delta = CanvasInteractionView.keyboardNudgeDelta(for: event) else {
            return false
        }

        state.nudgeSelected(by: delta)
        return true
    }
}

private final class CanvasKeyMonitor {
    private var token: Any?

    deinit {
        if let token {
            NSEvent.removeMonitor(token)
        }
    }

    func install(handler: @escaping (NSEvent) -> NSEvent?) {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
    }
}

struct CanvasView: NSViewRepresentable {
    @ObservedObject var state: EditorState
    @ObservedObject var focusProxy: CanvasFocusProxy
    @ObservedObject var zoomController: CanvasZoomController
    /// Width of the viewport slice the inspector column covers on the right;
    /// scales with the window, so it is pushed in on every update.
    var rightOcclusion: CGFloat = Theme.rightChromeWidth
    /// Customizable keyboard shortcuts, handled by the interaction view's
    /// responder chain (no system beep, unlike a swallowing event monitor).
    var shortcutActions: [ShortcutCommand: () -> Void] = [:]

    func makeCoordinator() -> CanvasCoordinator { CanvasCoordinator() }

    func makeNSView(context: Context) -> CanvasScrollView {
        focusProxy.attach(context.coordinator.interactionView, state: state)
        zoomController.attach(context.coordinator)
        context.coordinator.updateRightOcclusion(rightOcclusion)
        context.coordinator.interactionView.shortcutActions = shortcutActions
        context.coordinator.update(state: state)
        return context.coordinator.scrollView
    }

    func updateNSView(_ nsView: CanvasScrollView, context: Context) {
        // SwiftUI re-invokes this whenever the observed EditorState changes
        // (e.g. document mutated). All on the main actor — safe to touch AppKit.
        focusProxy.attach(context.coordinator.interactionView, state: state)
        zoomController.attach(context.coordinator)
        context.coordinator.updateRightOcclusion(rightOcclusion)
        context.coordinator.interactionView.shortcutActions = shortcutActions
        context.coordinator.update(state: state)
    }
}

extension NSWindow {
    var firstResponderAcceptsTextInput: Bool {
        guard let firstResponder else { return false }

        var responder: NSResponder? = firstResponder
        while let current = responder {
            if current is NSTextView || current is NSTextField {
                return true
            }
            responder = current.nextResponder
        }

        return false
    }
}
