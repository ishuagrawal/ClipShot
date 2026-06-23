import AppKit
import Carbon.HIToolbox
import XCTest
@testable import ClipShot

@MainActor
final class ShortcutTests: XCTestCase {

    // MARK: - KeyBinding

    func testDisplayStringOrdersModifiersAndKey() {
        let binding = KeyBinding(keyCode: UInt16(kVK_ANSI_5), modifiers: [.control, .shift])
        XCTAssertEqual(binding.displayString, "⌃⇧5")
    }

    func testDisplayComponentsSplitsGlyphs() {
        let binding = KeyBinding(keyCode: UInt16(kVK_ANSI_Z), modifiers: [.command, .shift])
        XCTAssertEqual(binding.displayComponents, ["⇧", "⌘", "Z"])
    }

    func testModifierNormalizationDropsNonStandardFlags() {
        let withJunk = KeyBinding(keyCode: 0, modifiers: [.command, .numericPad, .capsLock])
        let clean = KeyBinding(keyCode: 0, modifiers: [.command])
        XCTAssertEqual(withJunk.modifiers, clean.modifiers)
    }

    func testCarbonModifiersTranslation() {
        let binding = KeyBinding(keyCode: 0, modifiers: [.control, .shift])
        XCTAssertEqual(binding.carbonModifiers, UInt32(controlKey) | UInt32(shiftKey))
    }

    func testCodableRoundTrip() throws {
        let binding = KeyBinding(keyCode: UInt16(kVK_ANSI_C), modifiers: [.command])
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(KeyBinding.self, from: data)
        XCTAssertEqual(binding, decoded)
    }

    // MARK: - ShortcutStore

    private func makeStore() -> ShortcutStore {
        let suite = "ShortcutTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return ShortcutStore(defaults: defaults)
    }

    private func makeStore(globalShortcutIsAvailable: @escaping @Sendable (KeyBinding) -> Bool) -> ShortcutStore {
        let suite = "ShortcutTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return ShortcutStore(defaults: defaults, globalShortcutIsAvailable: globalShortcutIsAvailable)
    }

    func testDefaultsReturnedWhenNoOverride() {
        let store = makeStore()
        XCTAssertEqual(store.binding(for: .capture), ShortcutCommand.capture.defaultBinding)
    }

    func testSetBindingSucceedsAndPersists() {
        let suite = "ShortcutTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = ShortcutStore(defaults: defaults)
        let binding = KeyBinding(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command])
        XCTAssertTrue(store.setBinding(binding, for: .copy))

        let reloaded = ShortcutStore(defaults: defaults)
        XCTAssertEqual(reloaded.binding(for: .copy), binding)
    }

    func testSetBindingBlockedOnConflict() {
        let store = makeStore()
        let copyDefault = ShortcutCommand.copy.defaultBinding
        XCTAssertFalse(store.setBinding(copyDefault, for: .save))
        XCTAssertEqual(store.binding(for: .save), ShortcutCommand.save.defaultBinding)
    }

    func testCaptureBindingRejectsBareKeys() {
        let store = makeStore(globalShortcutIsAvailable: { _ in true })
        let bareKey = KeyBinding(keyCode: UInt16(kVK_ANSI_C), modifiers: [])

        XCTAssertFalse(store.setBinding(bareKey, for: .capture))
        XCTAssertEqual(store.binding(for: .capture), ShortcutCommand.capture.defaultBinding)
    }

    func testCaptureBindingRejectsUnavailableGlobalHotkey() {
        let blocked = KeyBinding(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command, .shift])
        let store = makeStore(globalShortcutIsAvailable: { $0 != blocked })

        XCTAssertFalse(store.setBinding(blocked, for: .capture))
        XCTAssertEqual(store.binding(for: .capture), ShortcutCommand.capture.defaultBinding)
    }

    func testCaptureBindingAllowsAvailableGlobalHotkey() {
        let available = KeyBinding(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command, .shift])
        let store = makeStore(globalShortcutIsAvailable: { $0 == available })

        XCTAssertTrue(store.setBinding(available, for: .capture))
        XCTAssertEqual(store.binding(for: .capture), available)
    }

    func testRecordingGateDisablesCaptureShortcutWhileRecording() {
        var enabledStates: [Bool] = []
        let gate = ShortcutRecordingGate { enabledStates.append($0) }

        gate.beginRecording()

        XCTAssertEqual(enabledStates, [false])
    }

    func testRecordingGateRestoresCaptureShortcutWhenRecordingEnds() {
        var enabledStates: [Bool] = []
        let gate = ShortcutRecordingGate { enabledStates.append($0) }

        gate.beginRecording()
        gate.endRecording()

        XCTAssertEqual(enabledStates, [false, true])
    }

    func testRecordingGateDoesNotDuplicateDisableOrRestoreEvents() {
        var enabledStates: [Bool] = []
        let gate = ShortcutRecordingGate { enabledStates.append($0) }

        gate.beginRecording()
        gate.beginRecording()
        gate.endRecording()
        gate.endRecording()

        XCTAssertEqual(enabledStates, [false, true])
    }

    func testCommandOwningExcludesSelf() {
        let store = makeStore()
        let copyDefault = ShortcutCommand.copy.defaultBinding
        XCTAssertNil(store.commandOwning(copyDefault, excluding: .copy))
        XCTAssertEqual(store.commandOwning(copyDefault, excluding: nil), .copy)
    }

    func testResetAndResetAll() {
        let store = makeStore()
        let binding = KeyBinding(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command])
        store.setBinding(binding, for: .copy)
        store.reset(.copy)
        XCTAssertEqual(store.binding(for: .copy), ShortcutCommand.copy.defaultBinding)

        store.setBinding(binding, for: .copy)
        store.resetAll()
        XCTAssertTrue(store.overrides.isEmpty)
        XCTAssertEqual(store.binding(for: .copy), ShortcutCommand.copy.defaultBinding)
    }

    func testNoDefaultBindingCollisions() {
        var seen: [KeyBinding: ShortcutCommand] = [:]
        for command in ShortcutCommand.allCases {
            let binding = command.defaultBinding
            XCTAssertNil(seen[binding], "\(command) collides with \(seen[binding]!) on \(binding.displayString)")
            seen[binding] = command
        }
    }
}
