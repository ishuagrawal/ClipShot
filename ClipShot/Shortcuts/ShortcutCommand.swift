import AppKit
import Carbon.HIToolbox

enum ShortcutCategory: String, CaseIterable, Sendable {
    case capture, editor, zoom, tools

    var displayName: String {
        switch self {
        case .capture: return "Capture"
        case .editor:  return "Editor"
        case .zoom:    return "Zoom"
        case .tools:   return "Tools"
        }
    }
}

/// Every bindable action. `rawValue` is the persistence key, so cases must not be
/// renamed without a migration.
enum ShortcutCommand: String, CaseIterable, Identifiable, Sendable {
    case capture
    case goHome
    case copy
    case save
    case undo
    case redo
    case resetAll
    case preview
    case zoomIn
    case zoomOut
    case resetZoom
    case toolSelect
    case toolArrow
    case toolLine
    case toolRectangle
    case toolText

    var id: String { rawValue }

    /// The capture hotkey is registered system-wide via Carbon; everything else is
    /// handled by the in-app event monitor.
    var isGlobal: Bool { self == .capture }

    var category: ShortcutCategory {
        switch self {
        case .capture:
            return .capture
        case .goHome, .copy, .save, .undo, .redo, .resetAll, .preview:
            return .editor
        case .zoomIn, .zoomOut, .resetZoom:
            return .zoom
        case .toolSelect, .toolArrow, .toolLine, .toolRectangle, .toolText:
            return .tools
        }
    }

    var displayName: String {
        switch self {
        case .capture:       return "Capture screenshot"
        case .goHome:        return "Go home"
        case .copy:          return "Copy"
        case .save:          return "Save"
        case .undo:          return "Undo"
        case .redo:          return "Redo"
        case .resetAll:      return "Reset all changes"
        case .preview:       return "Preview original"
        case .zoomIn:        return "Zoom in"
        case .zoomOut:       return "Zoom out"
        case .resetZoom:     return "Reset zoom"
        case .toolSelect:    return "Select tool"
        case .toolArrow:     return "Arrow tool"
        case .toolLine:      return "Line tool"
        case .toolRectangle: return "Rectangle tool"
        case .toolText:      return "Text tool"
        }
    }

    var defaultBinding: KeyBinding {
        switch self {
        case .capture:       return KeyBinding(keyCode: key(kVK_ANSI_5), modifiers: [.control, .shift])
        case .goHome:        return KeyBinding(keyCode: key(kVK_ANSI_H), modifiers: [.command])
        case .copy:          return KeyBinding(keyCode: key(kVK_ANSI_C), modifiers: [.command])
        case .save:          return KeyBinding(keyCode: key(kVK_ANSI_S), modifiers: [.command])
        case .undo:          return KeyBinding(keyCode: key(kVK_ANSI_Z), modifiers: [.command])
        case .redo:          return KeyBinding(keyCode: key(kVK_ANSI_Z), modifiers: [.command, .shift])
        case .resetAll:      return KeyBinding(keyCode: key(kVK_ANSI_R), modifiers: [.command, .shift])
        case .preview:       return KeyBinding(keyCode: key(kVK_ANSI_P), modifiers: [])
        case .zoomIn:        return KeyBinding(keyCode: key(kVK_ANSI_Equal), modifiers: [.command])
        case .zoomOut:       return KeyBinding(keyCode: key(kVK_ANSI_Minus), modifiers: [.command])
        case .resetZoom:     return KeyBinding(keyCode: key(kVK_ANSI_0), modifiers: [.command])
        case .toolSelect:    return KeyBinding(keyCode: key(kVK_ANSI_V), modifiers: [])
        case .toolArrow:     return KeyBinding(keyCode: key(kVK_ANSI_A), modifiers: [])
        case .toolLine:      return KeyBinding(keyCode: key(kVK_ANSI_L), modifiers: [])
        case .toolRectangle: return KeyBinding(keyCode: key(kVK_ANSI_R), modifiers: [])
        case .toolText:      return KeyBinding(keyCode: key(kVK_ANSI_T), modifiers: [])
        }
    }

    private func key(_ code: Int) -> UInt16 { UInt16(code) }
}
