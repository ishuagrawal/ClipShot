import CoreGraphics
import Foundation

/// Sets the card's uniform corner-radius override. `nil` restores auto
/// (concentric) rounding derived from the screenshot radius + padding.
struct SetCardCornerCommand: EditorCommand {
    let from: CGFloat?
    let to: CGFloat?

    var displayName: String { "Change corner radius" }

    func apply(to document: inout EditorDocument) {
        document.cardCornerOverride = to
    }

    func revert(to document: inout EditorDocument) {
        document.cardCornerOverride = from
    }

    func coalesce(with next: EditorCommand) -> EditorCommand? {
        guard let next = next as? SetCardCornerCommand else { return nil }
        return SetCardCornerCommand(from: from, to: next.to)
    }
}

/// Sets the screenshot's own corner-radius override and/or the lock-to-card flag.
/// `nil` radius restores the captured selection corners.
struct SetScreenshotCornerCommand: EditorCommand {
    let fromRadius: CGFloat?
    let toRadius: CGFloat?
    let fromLock: Bool
    let toLock: Bool

    var displayName: String { "Change screenshot corners" }

    func apply(to document: inout EditorDocument) {
        document.screenshotCornerOverride = toRadius
        document.lockCornersToCard = toLock
    }

    func revert(to document: inout EditorDocument) {
        document.screenshotCornerOverride = fromRadius
        document.lockCornersToCard = fromLock
    }

    func coalesce(with next: EditorCommand) -> EditorCommand? {
        guard let next = next as? SetScreenshotCornerCommand else { return nil }
        return SetScreenshotCornerCommand(
            fromRadius: fromRadius, toRadius: next.toRadius,
            fromLock: fromLock, toLock: next.toLock
        )
    }
}
