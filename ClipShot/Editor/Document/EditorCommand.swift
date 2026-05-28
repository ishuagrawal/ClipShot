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

protocol Clock: AnyObject {
    func currentTime() -> TimeInterval
}

final class SystemClock: Clock {
    func currentTime() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}
