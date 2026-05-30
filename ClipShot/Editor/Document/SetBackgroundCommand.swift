import Foundation

struct SetBackgroundCommand: EditorCommand {
    let from: BackgroundStyle
    let to: BackgroundStyle

    var displayName: String { "Change background" }

    func apply(to document: inout EditorDocument) {
        document.background = to
    }

    func revert(to document: inout EditorDocument) {
        document.background = from
    }

    func coalesce(with next: EditorCommand) -> EditorCommand? {
        guard let next = next as? SetBackgroundCommand else { return nil }
        return SetBackgroundCommand(from: from, to: next.to)
    }
}
