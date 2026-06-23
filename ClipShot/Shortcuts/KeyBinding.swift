import AppKit
import Carbon.HIToolbox

/// A single key combination: a virtual keycode plus the four standard modifiers.
/// Used for both the global capture hotkey (translated to Carbon) and in-app
/// matching against `NSEvent`.
struct KeyBinding: Codable, Equatable, Hashable, Sendable {
    var keyCode: UInt16
    /// `NSEvent.ModifierFlags` rawValue, masked to ⌘⌥⌃⇧ only.
    var modifiers: UInt

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = Self.normalized(modifiers)
    }

    /// Builds a binding from a keyDown event, or nil if the key is a bare modifier.
    init?(event: NSEvent) {
        guard !Self.isModifierKey(event.keyCode) else { return nil }
        self.keyCode = event.keyCode
        self.modifiers = Self.normalized(event.modifierFlags)
    }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode && Self.normalized(event.modifierFlags) == modifiers
    }

    var hasModifier: Bool { modifiers != 0 }

    static func normalized(_ flags: NSEvent.ModifierFlags) -> UInt {
        var result: NSEvent.ModifierFlags = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result.rawValue
    }

    private static func isModifierKey(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift,
             kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl,
             kVK_CapsLock, kVK_Function:
            return true
        default:
            return false
        }
    }

    // MARK: - Carbon (global hotkey)

    var carbonModifiers: UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }

    // MARK: - Display

    var displayString: String { displayComponents.joined() }

    /// Modifier glyphs (each its own element) followed by the key name; handy for
    /// rendering individual keycaps.
    var displayComponents: [String] {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyName(keyCode))
        return parts
    }

    /// Human label for a virtual keycode. Covers ANSI letters/digits/symbols the
    /// app binds plus the common special keys a user might record.
    static func keyName(_ keyCode: UInt16) -> String {
        if let name = specialKeyNames[Int(keyCode)] { return name }
        if let name = ansiKeyNames[Int(keyCode)] { return name }
        return "Key \(keyCode)"
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12"
    ]

    private static let ansiKeyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Equal: "=", kVK_ANSI_Minus: "-", kVK_ANSI_Slash: "/",
        kVK_ANSI_Period: ".", kVK_ANSI_Comma: ",", kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Quote: "'", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`"
    ]
}
