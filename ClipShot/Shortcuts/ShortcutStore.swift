import Combine
import Foundation

/// Source of truth for every command's binding. Overrides persist to UserDefaults;
/// any command without an override falls back to its default, so commands added in
/// later versions start at their default automatically.
@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    /// Only the overrides differing from defaults. Read through `binding(for:)`.
    @Published private(set) var overrides: [ShortcutCommand: KeyBinding]

    private let defaults: UserDefaults
    private let globalShortcutIsAvailable: @MainActor @Sendable (KeyBinding) -> Bool
    private let storageKey = "ClipShotShortcutBindings"

    init(
        defaults: UserDefaults = .standard,
        globalShortcutIsAvailable: @escaping @MainActor @Sendable (KeyBinding) -> Bool = NativeCaptureShortcut.isBindingAvailableForRegistration
    ) {
        self.defaults = defaults
        self.globalShortcutIsAvailable = globalShortcutIsAvailable
        self.overrides = Self.load(from: defaults, key: storageKey)
    }

    func binding(for command: ShortcutCommand) -> KeyBinding {
        overrides[command] ?? command.defaultBinding
    }

    /// The command currently bound to `binding`, if any (ignoring `excluding`).
    func commandOwning(_ binding: KeyBinding, excluding: ShortcutCommand?) -> ShortcutCommand? {
        ShortcutCommand.allCases.first { $0 != excluding && self.binding(for: $0) == binding }
    }

    /// Assigns the binding, or returns false (no change) if another command owns it.
    @discardableResult
    func setBinding(_ binding: KeyBinding, for command: ShortcutCommand) -> Bool {
        if commandOwning(binding, excluding: command) != nil { return false }
        if binding == self.binding(for: command) { return true }
        if command.isGlobal && !canUseGlobalBinding(binding) { return false }
        if binding == command.defaultBinding {
            overrides[command] = nil
        } else {
            overrides[command] = binding
        }
        persist()
        return true
    }

    private func canUseGlobalBinding(_ binding: KeyBinding) -> Bool {
        binding.hasModifier && globalShortcutIsAvailable(binding)
    }

    func reset(_ command: ShortcutCommand) {
        overrides[command] = nil
        persist()
    }

    func resetAll() {
        overrides = [:]
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        let raw = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(raw) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [ShortcutCommand: KeyBinding] {
        guard let data = defaults.data(forKey: key),
              let raw = try? JSONDecoder().decode([String: KeyBinding].self, from: data) else {
            return [:]
        }
        var result: [ShortcutCommand: KeyBinding] = [:]
        for (rawKey, binding) in raw {
            if let command = ShortcutCommand(rawValue: rawKey) { result[command] = binding }
        }
        return result
    }
}
