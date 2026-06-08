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

struct SetBackgroundEffectsCommand: EditorCommand {
    let from: BackgroundEffects
    let to: BackgroundEffects

    var displayName: String { "Change background effects" }

    func apply(to document: inout EditorDocument) {
        document.backgroundEffects = to
    }

    func revert(to document: inout EditorDocument) {
        document.backgroundEffects = from
    }

    func coalesce(with next: EditorCommand) -> EditorCommand? {
        guard let next = next as? SetBackgroundEffectsCommand else { return nil }
        return SetBackgroundEffectsCommand(from: from, to: next.to)
    }
}

struct SetShadowCommand: EditorCommand {
    let from: ShadowConfig
    let to: ShadowConfig

    var displayName: String { "Change shadow" }

    func apply(to document: inout EditorDocument) {
        document.shadow = to
    }

    func revert(to document: inout EditorDocument) {
        document.shadow = from
    }

    func coalesce(with next: EditorCommand) -> EditorCommand? {
        guard let next = next as? SetShadowCommand else { return nil }
        return SetShadowCommand(from: from, to: next.to)
    }
}
