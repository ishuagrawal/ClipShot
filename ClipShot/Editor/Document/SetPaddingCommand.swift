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
    let fromAutoCenter: EditorState.AutoCenterContext?
    let toAutoCenter: EditorState.AutoCenterContext?

    var displayName: String { "Auto-center" }

    init(
        fromScreenshot: CGImage,
        toScreenshot: CGImage,
        fromSelection: CGRect,
        toSelection: CGRect,
        fromPadding: PaddingConfig,
        toPadding: PaddingConfig,
        annotationDelta: CGSize,
        fromAutoCenter: EditorState.AutoCenterContext? = nil,
        toAutoCenter: EditorState.AutoCenterContext? = nil
    ) {
        self.fromScreenshot = fromScreenshot
        self.toScreenshot = toScreenshot
        self.fromSelection = fromSelection
        self.toSelection = toSelection
        self.fromPadding = fromPadding
        self.toPadding = toPadding
        self.annotationDelta = annotationDelta
        self.fromAutoCenter = fromAutoCenter
        self.toAutoCenter = toAutoCenter
    }

    func withAutoCenterContexts(
        from: EditorState.AutoCenterContext?,
        to: EditorState.AutoCenterContext?
    ) -> ApplyAutoCenterCommand {
        ApplyAutoCenterCommand(
            fromScreenshot: fromScreenshot,
            toScreenshot: toScreenshot,
            fromSelection: fromSelection,
            toSelection: toSelection,
            fromPadding: fromPadding,
            toPadding: toPadding,
            annotationDelta: annotationDelta,
            fromAutoCenter: from,
            toAutoCenter: to
        )
    }

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
