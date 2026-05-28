import Foundation

final class UndoStack {
    private struct Entry {
        let command: EditorCommand
        let timestamp: TimeInterval
    }

    let coalesceWindow: TimeInterval
    let clock: Clock

    private var undoEntries: [Entry] = []
    private var redoEntries: [Entry] = []
    private let maxEntries = 100

    init(coalesceWindow: TimeInterval = 0.5, clock: Clock = SystemClock()) {
        self.coalesceWindow = coalesceWindow
        self.clock = clock
    }

    var canUndo: Bool { !undoEntries.isEmpty }
    var canRedo: Bool { !redoEntries.isEmpty }
    var undoCount: Int { undoEntries.count }
    var redoCount: Int { redoEntries.count }

    /// Apply the command immediately, then record it for undo. Clears the redo stack.
    /// If the previous top of the stack coalesces with `command` and was pushed within
    /// `coalesceWindow`, the top entry is replaced by the merged command.
    func push(_ command: EditorCommand, apply: (EditorCommand) -> Void) {
        apply(command)
        redoEntries.removeAll()
        let now = clock.currentTime()

        if let top = undoEntries.last,
           now - top.timestamp <= coalesceWindow,
           let merged = top.command.coalesce(with: command) {
            // Rolling window (anchored to the previous command, not the first): a
            // continuous interaction like a slider drag collapses into ONE undo entry.
            // Discrete commands opt out via coalesce -> nil. Do not change to anchor on first.
            undoEntries[undoEntries.count - 1] = Entry(command: merged, timestamp: now)
            return
        }

        undoEntries.append(Entry(command: command, timestamp: now))
        if undoEntries.count > maxEntries {
            undoEntries.removeFirst(undoEntries.count - maxEntries)
        }
    }

    func undo(revert: (EditorCommand) -> Void) {
        guard let entry = undoEntries.popLast() else { return }
        revert(entry.command)
        redoEntries.append(entry)
    }

    func redo(apply: (EditorCommand) -> Void) {
        guard let entry = redoEntries.popLast() else { return }
        apply(entry.command)
        // Re-record on the undo stack; bump timestamp so a fresh coalesce window starts.
        undoEntries.append(Entry(command: entry.command, timestamp: clock.currentTime()))
    }
}
