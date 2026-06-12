import AppKit
import SwiftUI

@MainActor
final class EditorWindowController {
    private static let frameAutosaveName = NSWindow.FrameAutosaveName("ClipShotEditorWindow")

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

        // The system title is hidden (it lands beside the stoplights on this OS);
        // EditorView draws its own titlebar strip with the app name centered on
        // the stoplight row instead.
        window.title = "ClipShot"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Match the chrome surface so the transparent titlebar and any resize
        // overdraw blend into the drafting-room theme instead of flashing gray.
        window.backgroundColor = NSColor(red: 0.075, green: 0.067, blue: 0.059, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 860, height: 560)
        window.contentViewController = hostingController
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        return window
    }
}
