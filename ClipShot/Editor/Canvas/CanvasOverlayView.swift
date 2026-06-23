import AppKit
import CoreText

/// Sits above CanvasContentView inside the same documentView and draws annotations.
final class CanvasOverlayView: NSView {

    var document: EditorDocument? {
        didSet { updateDocument(previous: oldValue) }
    }

    var inProgressAnnotation: Annotation? {
        didSet {
            if oldValue != inProgressAnnotation {
                updateAnnotations()
            }
        }
    }

    var selectedAnnotationID: UUID? {
        didSet {
            if oldValue != selectedAnnotationID {
                updateAnnotations()
            }
        }
    }

    var hoveredAnnotationID: UUID? {
        didSet {
            if oldValue != hoveredAnnotationID {
                updateAnnotations()
            }
        }
    }

    var editingTextAnnotation: Annotation? {
        didSet {
            if oldValue != editingTextAnnotation {
                updateAnnotations()
            }
        }
    }

    /// Physical canvas magnification. Resize handles divide by it so they stay a
    /// constant on-screen size regardless of zoom.
    var zoomScale: CGFloat = 1 {
        didSet {
            if oldValue != zoomScale {
                updateAnnotations()
            }
        }
    }

    /// Hide resize handles while the selected annotation is being dragged/resized.
    var suppressResizeHandles = false {
        didSet {
            if oldValue != suppressResizeHandles {
                updateAnnotations()
            }
        }
    }

    private let annotationsLayer: CALayer
    private let annotationContentLayer: CALayer
    private var annotationLayers: [UUID: CALayer] = [:]
    private let inProgressLayerKey = UUID()

    override init(frame frameRect: NSRect) {
        annotationsLayer = CALayer()
        annotationContentLayer = CALayer()
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear

        annotationsLayer.addSublayer(annotationContentLayer)
        layer?.addSublayer(annotationsLayer)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override var isFlipped: Bool { true }

    /// Overlay covers the full screenshot document, same frame as CanvasContentView.
    /// Self-contained: sets the frame first, then assigns `document` so future
    /// overlay chrome is always drawn against the correct bounds.
    func resizeToDocument(_ doc: EditorDocument) {
        frame = doc.imageBounds
        document = doc
    }

    private func updateDocument(previous: EditorDocument?) {
        guard let doc = document else {
            annotationContentLayer.sublayers = nil
            annotationLayers.removeAll()
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let cardFrame = doc.effectiveCrop.integral
        annotationsLayer.frame = CGRect(origin: cardFrame.origin, size: cardFrame.size)

        if let radius = doc.cardCornerRadius {
            annotationsLayer.cornerCurve = .continuous
            annotationsLayer.cornerRadius = radius
            annotationsLayer.maskedCorners = [
                .layerMinXMinYCorner, .layerMaxXMinYCorner,
                .layerMinXMaxYCorner, .layerMaxXMaxYCorner
            ]
            annotationsLayer.masksToBounds = true
            annotationsLayer.mask = nil
        } else {
            annotationsLayer.cornerRadius = 0
            annotationsLayer.masksToBounds = false
            annotationsLayer.mask = nil
        }

        annotationContentLayer.frame = CGRect(
            x: doc.padding.left,
            y: doc.padding.top,
            width: doc.baseSelection.width,
            height: doc.baseSelection.height
        )
        annotationContentLayer.masksToBounds = false

        CATransaction.commit()
        if previous?.annotations != doc.annotations {
            updateAnnotations()
        }
    }

    private func updateAnnotations() {
        guard let doc = document else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        var liveIDs = Set<UUID>()
        for annotation in doc.annotations {
            liveIDs.insert(annotation.id)
            let editingAnnotation = editingTextAnnotation?.id == annotation.id ? editingTextAnnotation : nil
            let displayAnnotation = editingAnnotation ?? annotation
            let layer = annotationLayers[annotation.id] ?? makeLayer(for: annotation.id)
            configure(
                layer,
                with: displayAnnotation.kind,
                selected: annotation.id == selectedAnnotationID
                    || annotation.id == hoveredAnnotationID
                    || editingAnnotation != nil,
                rendersContent: editingAnnotation == nil,
                showsResizeHandles: annotation.id == selectedAnnotationID
                    && editingAnnotation == nil
                    && !suppressResizeHandles
            )
        }

        if let inProgressAnnotation {
            liveIDs.insert(inProgressLayerKey)
            let editingAnnotation = editingTextAnnotation?.id == inProgressAnnotation.id ? editingTextAnnotation : nil
            let displayAnnotation = editingAnnotation ?? inProgressAnnotation
            let layer = annotationLayers[inProgressLayerKey] ?? makeLayer(for: inProgressLayerKey)
            configure(
                layer,
                with: displayAnnotation.kind,
                selected: inProgressAnnotation.id == hoveredAnnotationID || editingAnnotation != nil,
                rendersContent: editingAnnotation == nil
            )
        }

        let staleIDs = annotationLayers.keys.filter { !liveIDs.contains($0) }
        for id in staleIDs {
            annotationLayers[id]?.removeFromSuperlayer()
            annotationLayers[id] = nil
        }
    }

    private func makeLayer(for id: UUID) -> CALayer {
        let container = CALayer()
        container.masksToBounds = false
        annotationContentLayer.addSublayer(container)
        annotationLayers[id] = container
        return container
    }

    private func configure(
        _ container: CALayer,
        with kind: Annotation.Kind,
        selected: Bool,
        rendersContent: Bool = true,
        showsResizeHandles: Bool = false
    ) {
        container.sublayers?.forEach { $0.removeFromSuperlayer() }
        container.sublayers = nil

        if rendersContent {
            switch kind {
            case .arrow(let from, let to, let pathStyle, let curve, let color, let weight, let borderColor):
                let activeCurve = AnnotationGeometry.arrowCurve(pathStyle: pathStyle, curve: curve)
                let linePath = AnnotationGeometry.arrowShaftPath(from: from, to: to, curve: activeCurve, weight: weight)
                let headPath = AnnotationGeometry.arrowHeadPath(from: from, to: to, curve: activeCurve, weight: weight)

                if let borderColor {
                    let borderWidth = AnnotationGeometry.arrowBorderWidth(weight: weight)
                    let borderLine = CAShapeLayer()
                    borderLine.path = linePath
                    borderLine.strokeColor = borderColor
                    borderLine.fillColor = nil
                    borderLine.lineWidth = weight + borderWidth * 2
                    borderLine.lineCap = .round
                    container.addSublayer(borderLine)

                    let borderHead = CAShapeLayer()
                    borderHead.path = headPath
                    borderHead.strokeColor = borderColor
                    borderHead.fillColor = borderColor
                    borderHead.lineWidth = borderWidth * 2
                    borderHead.lineJoin = .round
                    container.addSublayer(borderHead)
                }

                let line = CAShapeLayer()
                line.path = linePath
                line.strokeColor = color
                line.fillColor = nil
                line.lineWidth = weight
                line.lineCap = .round
                container.addSublayer(line)

                let head = CAShapeLayer()
                head.path = headPath
                head.fillColor = color
                container.addSublayer(head)

            case .line(let from, let to, let color, let weight, let dash):
                let line = CAShapeLayer()
                line.path = AnnotationGeometry.linePath(from: from, to: to)
                line.strokeColor = color
                line.fillColor = nil
                line.lineWidth = weight
                let style = AnnotationGeometry.dashStyle(dash, weight: weight)
                line.lineCap = style.cap == .round ? .round : .butt
                line.lineDashPattern = style.pattern?.map { NSNumber(value: Double($0)) }
                container.addSublayer(line)

            case .rect(let frame, let stroke, let fill, let weight, let corner):
                let shape = CAShapeLayer()
                shape.path = AnnotationGeometry.rectPath(frame: frame, cornerRadius: corner)
                shape.fillColor = fill
                shape.strokeColor = stroke
                shape.lineWidth = weight
                container.addSublayer(shape)

            case .text(let origin, let string, let fontSize, let color):
                let text = CATextLayer()
                let frame = AnnotationGeometry.textFrame(origin: origin, string: string, fontSize: fontSize)
                text.frame = frame
                text.string = string
                text.font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
                text.fontSize = fontSize
                text.foregroundColor = color
                text.contentsScale = window?.backingScaleFactor ?? 2
                text.isWrapped = false
                container.addSublayer(text)

            case .blur:
                break
            }
        }

        if selected {
            let halo = CAShapeLayer()
            let frame = AnnotationGeometry.boundingBox(kind).insetBy(dx: -3, dy: -3)
            halo.path = CGPath(roundedRect: frame, cornerWidth: 4, cornerHeight: 4, transform: nil)
            halo.fillColor = nil
            halo.strokeColor = Theme.accentCG.copy(alpha: 0.95)
            halo.lineWidth = 1.5
            halo.lineDashPattern = [4, 3]
            container.addSublayer(halo)
        }

        if showsResizeHandles {
            let scale = max(zoomScale, 0.0001)
            let side = 8 / scale
            for (_, point) in AnnotationGeometry.resizeHandles(kind) {
                let dot = CAShapeLayer()
                dot.path = CGPath(
                    rect: CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side),
                    transform: nil
                )
                dot.fillColor = NSColor.white.cgColor
                dot.strokeColor = Theme.accentCG
                dot.lineWidth = 1 / scale
                container.addSublayer(dot)
            }
        }
    }

    /// Overlay chrome is non-interactive — let clicks fall through to the canvas.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
