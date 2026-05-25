import AppKit

final class OverlayView: NSView {
    private let screenFrame: CGRect
    private var selectedGlobalRect: CGRect?
    private var allGlobalRects: [CGRect] = []
    private var label: String?
    private var index: Int?
    private var count: Int?

    init(screenFrame: CGRect) {
        self.screenFrame = screenFrame
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateSelection(
        globalCocoaRect: CGRect?,
        allGlobalCocoaRects: [CGRect],
        label: String?,
        index: Int?,
        count: Int?
    ) {
        selectedGlobalRect = globalCocoaRect
        allGlobalRects = allGlobalCocoaRects
        self.label = label
        self.index = index
        self.count = count
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let dimPath = NSBezierPath(rect: bounds)
        let selectedRect = localSelectionRect()

        if let selectedRect {
            let highlightPath = NSBezierPath(
                roundedRect: selectedRect.insetBy(dx: -2, dy: -2),
                xRadius: 7,
                yRadius: 7
            )
            dimPath.append(highlightPath)
            dimPath.windingRule = .evenOdd
        }

        NSColor.black.withAlphaComponent(0.18).setFill()
        dimPath.fill()

        drawAllCandidateOutlines(selectedRect: selectedRect)

        guard let selectedRect else {
            return
        }

        let outlinePath = NSBezierPath(
            roundedRect: selectedRect.insetBy(dx: -2, dy: -2),
            xRadius: 7,
            yRadius: 7
        )
        outlinePath.lineWidth = 3
        NSColor.systemBlue.setStroke()
        outlinePath.stroke()

        drawSelectionLabel(near: selectedRect)
    }

    private func drawAllCandidateOutlines(selectedRect: CGRect?) {
        let selectedIntegral = selectedRect?.integral
        let localRects = allGlobalRects.compactMap { localRect(fromGlobalRect: $0) }

        NSColor.systemBlue.withAlphaComponent(0.22).setStroke()
        for rect in localRects {
            guard rect.integral != selectedIntegral else {
                continue
            }

            let path = NSBezierPath(
                roundedRect: rect.insetBy(dx: -1, dy: -1),
                xRadius: 5,
                yRadius: 5
            )
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func localSelectionRect() -> CGRect? {
        guard let selectedGlobalRect else {
            return nil
        }

        return localRect(fromGlobalRect: selectedGlobalRect)
    }

    private func localRect(fromGlobalRect globalRect: CGRect) -> CGRect? {
        let localRect = CGRect(
            x: globalRect.minX - screenFrame.minX,
            y: globalRect.minY - screenFrame.minY,
            width: globalRect.width,
            height: globalRect.height
        )
        let clipped = bounds.intersection(localRect)
        return clipped.isNull || clipped.isEmpty ? nil : clipped
    }

    private func drawSelectionLabel(near selectedRect: CGRect) {
        guard let label, let index, let count else {
            return
        }

        let text = "\(label)  \(index)/\(count)"
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]

        let maxWidth: CGFloat = min(280, bounds.width - 24)
        let measuredSize = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth - 20, height: 40),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        ).size

        let labelSize = CGSize(
            width: min(maxWidth, ceil(measuredSize.width) + 20),
            height: ceil(measuredSize.height) + 10
        )

        var origin = CGPoint(
            x: selectedRect.minX,
            y: selectedRect.maxY + 8
        )

        if origin.y + labelSize.height > bounds.maxY - 8 {
            origin.y = selectedRect.minY - labelSize.height - 8
        }

        origin.x = max(12, min(origin.x, bounds.maxX - labelSize.width - 12))
        origin.y = max(12, min(origin.y, bounds.maxY - labelSize.height - 12))

        let labelRect = CGRect(origin: origin, size: labelSize)
        let backgroundPath = NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5)
        NSColor.systemBlue.withAlphaComponent(0.96).setFill()
        backgroundPath.fill()

        let textRect = labelRect.insetBy(dx: 10, dy: 5)
        (text as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }
}
