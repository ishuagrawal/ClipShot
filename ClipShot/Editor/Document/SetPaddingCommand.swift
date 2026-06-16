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

/// Crops the screenshot to the detected content bbox and equalizes the four
/// margins. Annotations are translated by the crop-origin delta so they stay
/// glued to the same content pixels; revert restores everything exactly.
struct ApplyAutoCenterCommand: EditorCommand {
    let fromSelection: CGRect
    let toSelection: CGRect
    let fromPadding: PaddingConfig
    let toPadding: PaddingConfig

    var displayName: String { "Auto-center" }

    func apply(to document: inout EditorDocument) {
        document.baseSelection = toSelection
        document.padding = toPadding
        translateAnnotations(&document, from: fromSelection, to: toSelection)
    }

    func revert(to document: inout EditorDocument) {
        document.baseSelection = fromSelection
        document.padding = fromPadding
        translateAnnotations(&document, from: toSelection, to: fromSelection)
    }

    private func translateAnnotations(_ document: inout EditorDocument, from: CGRect, to: CGRect) {
        let delta = CGSize(width: from.minX - to.minX, height: from.minY - to.minY)
        guard delta != .zero else { return }
        for index in document.annotations.indices {
            document.annotations[index].kind = AnnotationGeometry.translated(document.annotations[index].kind, by: delta)
        }
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
