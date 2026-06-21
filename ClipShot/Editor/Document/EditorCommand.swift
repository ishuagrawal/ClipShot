import Foundation

protocol EditorCommand {
    var displayName: String { get }
    func apply(to document: inout EditorDocument)
    func revert(to document: inout EditorDocument)
    /// Return a merged command if `self` and `next` should be combined into one undo entry, else nil.
    func coalesce(with next: EditorCommand) -> EditorCommand?
}

/// Default: never coalesce.
extension EditorCommand {
    func coalesce(with next: EditorCommand) -> EditorCommand? { nil }
}

/// Trivial command used by tests; performs no document mutation.
struct NoOpCommand: EditorCommand {
    var displayName: String { "No-op" }
    func apply(to document: inout EditorDocument) {}
    func revert(to document: inout EditorDocument) {}
}

/// Reverts every editable field to a snapshot. Resets to the original loaded state
/// while staying undoable through the normal command stack.
struct ResetDocumentCommand: EditorCommand {
    let before: EditorDocument
    let original: EditorDocument

    var displayName: String { "Reset to Original" }

    func apply(to document: inout EditorDocument) { restore(original, into: &document) }
    func revert(to document: inout EditorDocument) { restore(before, into: &document) }

    private func restore(_ s: EditorDocument, into d: inout EditorDocument) {
        d.screenshot = s.screenshot
        d.baseSelection = s.baseSelection
        d.padding = s.padding
        d.background = s.background
        d.annotations = s.annotations
        d.shadow = s.shadow
        d.backgroundEffects = s.backgroundEffects
        d.screenshotCornerOverride = s.screenshotCornerOverride
    }
}

extension EditorDocument {
    /// True when user-editable state matches `other`, ignoring the version token.
    /// `screenshot` compared by identity (never reassigned in normal editing).
    func hasSameEdits(as other: EditorDocument) -> Bool {
        screenshot === other.screenshot &&
        baseSelection == other.baseSelection &&
        padding == other.padding &&
        background == other.background &&
        annotations == other.annotations &&
        shadow == other.shadow &&
        backgroundEffects == other.backgroundEffects &&
        screenshotCornerOverride == other.screenshotCornerOverride
    }
}

protocol Clock: AnyObject {
    func currentTime() -> TimeInterval
}

final class SystemClock: Clock {
    func currentTime() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}
