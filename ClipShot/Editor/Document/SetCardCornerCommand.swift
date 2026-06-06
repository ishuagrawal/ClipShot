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
