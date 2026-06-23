import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Tabbed settings window.
struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case general
        case keyboard
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: "General"
            case .keyboard: "Keyboard Shortcuts"
            }
        }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .keyboard: "keyboard"
            }
        }
    }

    @State private var tab: Tab = .general

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(16)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            switch tab {
            case .general: GeneralSettingsView()
            case .keyboard: KeyboardShortcutsView()
            }
        }
        .frame(minWidth: 480, minHeight: 560)
        .background(Theme.canvas)
        .preferredColorScheme(.dark)
    }
}

/// Lists every command grouped by category, each with its current binding, a
/// click-to-record chip, and a per-row reset.
struct KeyboardShortcutsView: View {
    @ObservedObject private var store = ShortcutStore.shared
    @State private var recording: ShortcutCommand?
    @State private var conflicts: [ShortcutCommand: String] = [:]
    @State private var monitor: Any?
    @State private var recordingGate = ShortcutRecordingGate()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(ShortcutCategory.allCases, id: \.self) { category in
                        let commands = ShortcutCommand.allCases.filter { $0.category == category }
                        if !commands.isEmpty {
                            section(category, commands)
                        }
                    }
                }
                .padding(20)
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            resetAllBar
        }
        .onDisappear { endRecording() }
    }

    private func section(_ category: ShortcutCategory, _ commands: [ShortcutCommand]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.displayName.uppercased())
                .font(Theme.label(10.5, .semibold))
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.2)
            VStack(spacing: 2) {
                ForEach(commands) { command in
                    row(command)
                }
            }
        }
    }

    private func row(_ command: ShortcutCommand) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack {
                Text(command.displayName)
                    .font(Theme.label(13))
                    .foregroundStyle(Theme.textPrimary)
                if command.isGlobal {
                    Text("system-wide")
                        .font(Theme.label(10))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                }
                Spacer()
                bindingChip(command)
                resetButton(command)
            }
            if let message = conflicts[command] {
                Text(message)
                    .font(Theme.label(11))
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    private func bindingChip(_ command: ShortcutCommand) -> some View {
        let isRecording = recording == command
        return Button {
            isRecording ? endRecording() : beginRecording(command)
        } label: {
            Text(isRecording ? "Press keys…" : store.binding(for: command).displayString)
                .font(Theme.title(12.5))
                .foregroundStyle(isRecording ? Theme.accent : Theme.textPrimary)
                .frame(minWidth: 64)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(isRecording ? Theme.accent : .clear, lineWidth: 1.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .help("Click, then press the new shortcut")
    }

    private func resetButton(_ command: ShortcutCommand) -> some View {
        let isDefault = store.binding(for: command) == command.defaultBinding
        return Button {
            store.reset(command)
            conflicts[command] = nil
            if recording == command { endRecording() }
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .opacity(isDefault ? 0.25 : 1)
        .disabled(isDefault)
        .help("Reset to default")
    }

    private var resetAllBar: some View {
        HStack {
            Spacer()
            Button("Reset all to defaults") {
                endRecording()
                conflicts = [:]
                store.resetAll()
            }
            .buttonStyle(.plain)
            .font(Theme.label(12))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.07)))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.canvas)
    }

    // MARK: - Recording

    private func beginRecording(_ command: ShortcutCommand) {
        endRecording()
        conflicts[command] = nil
        recording = command
        recordingGate.beginRecording()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleRecording(event)
            return nil
        }
    }

    private func handleRecording(_ event: NSEvent) {
        guard let command = recording else { return }
        if Int(event.keyCode) == kVK_Escape {
            endRecording()
            return
        }
        guard let binding = KeyBinding(event: event) else { return }
        if let owner = store.commandOwning(binding, excluding: command) {
            conflicts[command] = "Already used by \(owner.displayName)"
            endRecording()
            return
        }
        guard store.setBinding(binding, for: command) else {
            conflicts[command] = command.isGlobal ? "Shortcut unavailable" : "Already used"
            endRecording()
            return
        }
        endRecording()
    }

    private func endRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        recordingGate.endRecording()
    }
}

/// Default save location and other general preferences.
struct GeneralSettingsView: View {
    @ObservedObject private var store = GeneralSettingsStore.shared
    @State private var panelOpen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                saveLocationSection
            }
            .padding(20)
        }
    }

    private var saveLocationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SAVE LOCATION")
                .font(Theme.label(10.5, .semibold))
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.2)

            Button(action: pickDirectory) {
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(store.displayPath)
                        .font(Theme.label(13))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
            }
            .buttonStyle(.plain)
            .help("Click to choose a different folder")

            Text("Images save to this folder by default.")
                .font(Theme.label(11))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func pickDirectory() {
        guard !panelOpen else { return }
        panelOpen = true
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = store.saveDirectoryURL
        panel.prompt = "Choose"
        panel.message = "Select the default folder for saved images"
        panel.begin { response in
            Task { @MainActor in
                panelOpen = false
                guard response == .OK, let url = panel.url else { return }
                store.setSaveDirectory(url)
            }
        }
    }
}
