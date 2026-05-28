import AppKit
import SwiftUI

@MainActor
final class EditorWindowController {
    private let store: DOMCaptureSessionStore
    private var window: NSWindow?

    init(store: DOMCaptureSessionStore) {
        self.store = store
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let contentView = EditorView(store: store)
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "ClipShot"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 860, height: 560)
        window.contentViewController = hostingController
        window.center()
        return window
    }
}
