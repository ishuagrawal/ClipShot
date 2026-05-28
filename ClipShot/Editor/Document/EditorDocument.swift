import CoreGraphics
import Foundation

struct EditorDocument {
    let screenshot: CGImage
    let viewport: CGSize
    let pageTitle: String
    let pageURL: String

    let baseSelection: CGRect       // imagePx coords, clamped to ≥ 8×8 on init
    var padding: PaddingConfig      { didSet { bumpVersion() } }
    var background: BackgroundStyle { didSet { bumpVersion() } }
    var annotations: [Annotation]   { didSet { bumpVersion() } }
    private(set) var version: Int

    init(
        screenshot: CGImage,
        viewport: CGSize,
        pageTitle: String,
        pageURL: String,
        baseSelection: CGRect,
        padding: PaddingConfig = .zero,
        background: BackgroundStyle = .none,
        annotations: [Annotation] = []
    ) {
        self.screenshot = screenshot
        self.viewport = viewport
        self.pageTitle = pageTitle
        self.pageURL = pageURL
        let minSide: CGFloat = 8
        self.baseSelection = CGRect(
            x: baseSelection.origin.x,
            y: baseSelection.origin.y,
            width: max(minSide, baseSelection.width),
            height: max(minSide, baseSelection.height)
        )
        self.padding = padding
        self.background = background
        self.annotations = annotations
        self.version = 0
    }

    private mutating func bumpVersion() { version &+= 1 }

    var effectiveCrop: CGRect {
        CGRect(
            x: baseSelection.minX - padding.left,
            y: baseSelection.minY - padding.top,
            width: baseSelection.width + padding.left + padding.right,
            height: baseSelection.height + padding.top + padding.bottom
        )
    }

    var paddedDocumentSize: CGSize { effectiveCrop.size }
}

// CGImage is not Equatable by default; compare by identity for our purposes.
extension EditorDocument: Equatable {
    static func == (lhs: EditorDocument, rhs: EditorDocument) -> Bool {
        lhs.screenshot === rhs.screenshot
        && lhs.viewport == rhs.viewport
        && lhs.pageTitle == rhs.pageTitle
        && lhs.pageURL == rhs.pageURL
        && lhs.baseSelection == rhs.baseSelection
        && lhs.padding == rhs.padding
        && lhs.background == rhs.background
        && lhs.annotations == rhs.annotations
        && lhs.version == rhs.version
    }
}
