import SwiftUI

@main
struct ClipShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(appState)
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
        .commands {
            // Puts a "Settings…" item (⌘,) in the system app menu, opening the
            // same window as the menu-bar row and Home gear.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { AppState.shared.onOpenSettings?() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    private static let menuBarIcon: NSImage = {
        let image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "ClipShot")!
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
}

