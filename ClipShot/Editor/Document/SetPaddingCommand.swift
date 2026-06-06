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

struct ApplyAutoPaddingCommand: EditorCommand {
    let fromPadding: PaddingConfig
    let toPadding: PaddingConfig
    let fromBackground: BackgroundStyle
    let toBackground: BackgroundStyle

    var displayName: String { "Auto layout" }

    func apply(to document: inout EditorDocument) {
        document.padding = toPadding
        document.background = toBackground
    }

    func revert(to document: inout EditorDocument) {
        document.padding = fromPadding
        document.background = fromBackground
    }
}
