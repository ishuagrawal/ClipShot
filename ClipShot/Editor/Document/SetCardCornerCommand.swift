import CoreGraphics
import Foundation

/// Sets the screenshot's own corner-radius override. `nil` restores the captured
/// selection corners.
struct SetScreenshotCornerCommand: EditorCommand {
    let fromRadius: CGFloat?
    let toRadius: CGFloat?

    var displayName: String { "Change screenshot corners" }

    func apply(to document: inout EditorDocument) {
        document.screenshotCornerOverride = toRadius
    }

    func revert(to document: inout EditorDocument) {
        document.screenshotCornerOverride = fromRadius
    }

    func coalesce(with next: EditorCommand) -> EditorCommand? {
        guard let next = next as? SetScreenshotCornerCommand else { return nil }
        return SetScreenshotCornerCommand(fromRadius: fromRadius, toRadius: next.toRadius)
    }
}
