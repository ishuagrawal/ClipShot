import AppKit
import CoreText

/// Sits above CanvasContentView inside the same documentView. Draws the export
/// composite at `effectiveCrop` so padding/background preview matches output.
final class CanvasOverlayView: NSView {

    var document: EditorDocument? {
        didSet { updatePreview() }
    }

    var inProgressAnnotation: Annotation? {
        didSet { updateAnnotations() }
    }

    var selectedAnnotationID: UUID? {
        didSet { updateAnnotations() }
    }

    var editingTextAnnotation: Annotation? {
        didSet { updateAnnotations() }
    }

    private let previewLayer: CALayer
    private let annotationsLayer: CALayer
    private var annotationLayers: [UUID: CALayer] = [:]
    private let inProgressLayerKey = UUID()

    override init(frame frameRect: NSRect) {
        previewLayer = CALayer()
        annotationsLayer = CALayer()
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear

        previewLayer.contentsGravity = .resize
        previewLayer.magnificationFilter = .trilinear
        previewLayer.minificationFilter = .trilinear
        layer?.addSublayer(previewLayer)
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

    private func updatePreview() {
        guard let doc = document else {
            previewLayer.contents = nil
            previewLayer.isHidden = true
            annotationsLayer.sublayers = nil
            annotationLayers.removeAll()
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let hasFrame = doc.padding != .zero || doc.background != .none
        if hasFrame {
            previewLayer.frame = doc.effectiveCrop.integral
            previewLayer.contents = DocumentRenderer.render(makeFrameOnlyDocument(doc))
            previewLayer.isHidden = false
        } else {
            previewLayer.contents = nil
            previewLayer.isHidden = true
        }

        annotationsLayer.frame = CGRect(origin: doc.effectiveCrop.origin, size: doc.effectiveCrop.size)

        CATransaction.commit()
        updateAnnotations()
    }

    private func makeFrameOnlyDocument(_ document: EditorDocument) -> EditorDocument {
        var copy = document
        copy.annotations = []
        return copy
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
                selected: annotation.id == selectedAnnotationID || editingAnnotation != nil,
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
                selected: editingAnnotation != nil,
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
        annotationsLayer.addSublayer(container)
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
