import CoreGraphics
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

/// Replaces the card with a composited image — the detected content surrounded by
/// an equal band of synthesized background-colored whitespace — and equalizes the
/// outer padding. Annotations are translated to stay glued to the content; revert
/// restores the original card, selection, padding, and annotations exactly.
struct ApplyAutoCenterCommand: EditorCommand {
    let fromScreenshot: CGImage
    let toScreenshot: CGImage
    let fromSelection: CGRect
    let toSelection: CGRect
    let fromPadding: PaddingConfig
    let toPadding: PaddingConfig
    let annotationDelta: CGSize

    var displayName: String { "Auto-center" }

    func apply(to document: inout EditorDocument) {
        document.screenshot = toScreenshot
        document.baseSelection = toSelection
        document.padding = toPadding
        translateAnnotations(&document, by: annotationDelta)
    }

    func revert(to document: inout EditorDocument) {
        document.screenshot = fromScreenshot
        document.baseSelection = fromSelection
        document.padding = fromPadding
        translateAnnotations(&document, by: CGSize(width: -annotationDelta.width, height: -annotationDelta.height))
    }

    private func translateAnnotations(_ document: inout EditorDocument, by delta: CGSize) {
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
