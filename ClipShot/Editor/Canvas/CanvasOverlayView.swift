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

    private let annotationsLayer: CALayer
    private let annotationContentLayer: CALayer
    private let annotationsOuterMaskLayer: CAShapeLayer
    private let annotationsImageMaskLayer: CALayer
    private var annotationLayers: [UUID: CALayer] = [:]
    private let inProgressLayerKey = UUID()

    override init(frame frameRect: NSRect) {
        annotationsLayer = CALayer()
        annotationContentLayer = CALayer()
        annotationsOuterMaskLayer = CAShapeLayer()
        annotationsImageMaskLayer = CALayer()
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

        annotationsLayer.cornerRadius = 0
        annotationsLayer.masksToBounds = false
        if let card = ConcentricCardMask.coverage(for: doc) {
            annotationsImageMaskLayer.frame = annotationsLayer.bounds
            annotationsImageMaskLayer.contents = card.alpha
            annotationsImageMaskLayer.contentsGravity = .resize
            annotationsLayer.mask = annotationsImageMaskLayer
        } else if !doc.outerCornerRadii.isZero {
            annotationsOuterMaskLayer.frame = annotationsLayer.bounds
            annotationsOuterMaskLayer.path = doc.outerCornerRadii.path(in: annotationsOuterMaskLayer.bounds)
            annotationsLayer.mask = annotationsOuterMaskLayer
        } else {
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
                rendersContent: editingAnnotation == nil
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
        rendersContent: Bool = true
    ) {
        container.sublayers?.forEach { $0.removeFromSuperlayer() }
        container.sublayers = nil

        if rendersContent {
            switch kind {
            case .arrow(let from, let to, let color, let weight):
                let line = CAShapeLayer()
                line.path = AnnotationGeometry.arrowLinePath(from: from, to: to, weight: weight)
                line.strokeColor = color
                line.fillColor = nil
                line.lineWidth = weight
                line.lineCap = .round
                container.addSublayer(line)

                let head = CAShapeLayer()
                head.path = AnnotationGeometry.arrowHeadPath(from: from, to: to, weight: weight)
                head.fillColor = color
                container.addSublayer(head)

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
            halo.strokeColor = CGColor(red: 0.157, green: 0.792, blue: 0.722, alpha: 0.95)
            halo.lineWidth = 1.5
            halo.lineDashPattern = [4, 3]
            container.addSublayer(halo)
        }
    }

    /// Overlay chrome is non-interactive — let clicks fall through to the canvas.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
