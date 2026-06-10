import SwiftUI

@main
struct ClipShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra("ClipShot", systemImage: "viewfinder") {
            MenuContentView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}

