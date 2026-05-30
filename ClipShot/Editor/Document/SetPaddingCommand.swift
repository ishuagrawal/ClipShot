import Foundation

struct SetPaddingCommand: EditorCommand {
    let from: PaddingConfig
    let to: PaddingConfig

    var displayName: String { "Change padding" }

    func apply(to document: inout EditorDocument) {
        document.padding = to
    }

    func revert(to document: inout EditorDocument) {
        document.padding = from
    }

    func coalesce(with next: EditorCommand) -> EditorCommand? {
        guard let next = next as? SetPaddingCommand else { return nil }
        return SetPaddingCommand(from: from, to: next.to)
    }
}
