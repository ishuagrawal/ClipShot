import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// Pure, deterministic flattener of the export crop. The in-place canvas preview
/// reuses this output so Copy/Save and preview stay identical.
enum DocumentRenderer {

    static func dynamicBackgroundImage(for screenshot: CGImage, selection: CGRect, size: CGSize) -> CGImage? {
        DynamicMeshCache.shared.meshImage(for: screenshot, selection: selection, size: size)
    }

    static func render(_ doc: EditorDocument) -> CGImage? {
        let cropPx = doc.effectiveCrop.integral
        let width = Int(cropPx.width)
        let height = Int(cropPx.height)
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }

        // Establish y-down (top-left origin) document space for future annotation drawing.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let outputRect = CGRect(x: 0, y: 0, width: width, height: height)
        let selectionPx = doc.baseSelection.integral.intersection(doc.imageBounds)
        let dest = CGRect(
            x: selectionPx.minX - cropPx.minX,
            y: selectionPx.minY - cropPx.minY,
            width: selectionPx.width,
            height: selectionPx.height
        )

        if let radius = doc.cardCornerRadius,
           let mask = ConcentricCardMask.mask(width: width, height: height, radius: radius) {
            ctx.clip(to: outputRect, mask: mask)
        } else if !doc.outerCornerRadii.isZero {
            ctx.addPath(doc.outerCornerRadii.path(in: outputRect))
            ctx.clip()
        }

        if !doc.padding.isZero {
            drawBackground(doc.background, in: ctx, outputRect: outputRect,
                           screenshot: doc.screenshot, selection: doc.baseSelection)
        }
        ctx.saveGState()
        if !doc.padding.isZero {
            applyCardShadow(in: ctx, dest: dest)
        }
        drawScreenshot(
            doc.screenshot,
            selectionPx: selectionPx,
            dest: dest,
            cornerRadii: doc.selectionCornerRadii,
            in: ctx
        )
        ctx.restoreGState()
        ctx.saveGState()
        ctx.translateBy(x: doc.padding.left, y: doc.padding.top)
        drawAnnotations(doc.annotations, in: ctx)
        ctx.restoreGState()

        return ctx.makeImage()
    }

    private static func drawAnnotations(_ annotations: [Annotation], in ctx: CGContext) {
        for annotation in annotations {
            switch annotation.kind {
            case .arrow(let from, let to, let color, let weight):
                drawArrow(from: from, to: to, color: color, weight: weight, in: ctx)
            case .rect(let frame, let stroke, let fill, let weight, let corner):
                drawRect(frame: frame, stroke: stroke, fill: fill, weight: weight, corner: corner, in: ctx)
            case .text(let origin, let string, let fontSize, let color):
                drawText(origin: origin, string: string, fontSize: fontSize, color: color, in: ctx)
            case .blur:
                break
            }
        }
    }

    private static func drawArrow(
        from: CGPoint,
        to: CGPoint,
        color: CGColor,
        weight: CGFloat,
        in ctx: CGContext
    ) {
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(weight)
        ctx.setLineCap(.round)
        ctx.addPath(AnnotationGeometry.arrowLinePath(from: from, to: to, weight: weight))
        ctx.strokePath()
        ctx.addPath(AnnotationGeometry.arrowHeadPath(from: from, to: to, weight: weight))
        ctx.fillPath()
        ctx.restoreGState()
    }

    private static func drawRect(
        frame: CGRect,
        stroke: CGColor?,
        fill: CGColor?,
        weight: CGFloat,
        corner: CGFloat,
        in ctx: CGContext
    ) {
        ctx.saveGState()
        let path = AnnotationGeometry.rectPath(frame: frame, cornerRadius: corner)
        if let fill {
            ctx.addPath(path)
            ctx.setFillColor(fill)
            ctx.fillPath()
        }
        if let stroke {
            ctx.addPath(path)
            ctx.setStrokeColor(stroke)
            ctx.setLineWidth(weight)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private static func drawText(
        origin: CGPoint,
        string: String,
        fontSize: CGFloat,
        color: CGColor,
        in ctx: CGContext
    ) {
        guard !string.isEmpty else { return }
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let line = CTLineCreateWithAttributedString(
            AnnotationGeometry.attributedText(string, fontSize: fontSize, color: color)
        )
        let ascent = CTFontGetAscent(font)

        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = CGPoint(x: 0, y: -ascent)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private static func drawBackground(
        _ style: BackgroundStyle,
        in ctx: CGContext,
        outputRect: CGRect,
        screenshot: CGImage,
        selection: CGRect
    ) {
        switch style {
        case .none:
            break
        case .solidColor(let color):
            ctx.saveGState()
            ctx.setFillColor(color)
            ctx.fill(outputRect)
            ctx.restoreGState()
        case .gradient(let start, let end, let angleDegrees):
            drawGradient(start: start, end: end, angleDegrees: angleDegrees, in: ctx, rect: outputRect)
        case .dynamic:
            drawDynamic(in: ctx, outputRect: outputRect, screenshot: screenshot, selection: selection)
        }
    }

    private static func drawDynamic(
        in ctx: CGContext,
        outputRect: CGRect,
        screenshot: CGImage,
        selection: CGRect
    ) {
        guard let mesh = DynamicMeshCache.shared.meshImage(
            for: screenshot, selection: selection, size: outputRect.size
        ) else { return }
        ctx.saveGState()
        ctx.clip(to: outputRect)
        ctx.translateBy(x: outputRect.minX, y: outputRect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(mesh, in: CGRect(origin: .zero, size: outputRect.size))
        ctx.restoreGState()
    }

    private static func drawGradient(
        start: CGColor,
        end: CGColor,
        angleDegrees: CGFloat,
        in ctx: CGContext,
        rect: CGRect
    ) {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [start, end] as CFArray,
            locations: [0, 1]
        ) else { return }

        let radians = angleDegrees * .pi / 180
        let dx = cos(radians)
        let dy = sin(radians)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let half = max(rect.width, rect.height)
        let startPoint = CGPoint(x: center.x - dx * half / 2, y: center.y - dy * half / 2)
        let endPoint = CGPoint(x: center.x + dx * half / 2, y: center.y + dy * half / 2)

        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(
            gradient,
            start: startPoint,
            end: endPoint,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        ctx.restoreGState()
    }

    private static func applyCardShadow(in ctx: CGContext, dest: CGRect) {
        let shortSide = min(dest.width, dest.height)
        let blur = max(12, shortSide * 0.03)
        // Context is y-flipped (top-left origin), so a negative dy casts the
        // shadow visually downward — light-from-above, card sits above its shadow.
        let offset = CGSize(width: 0, height: -max(3, shortSide * 0.012))
        ctx.setShadow(
            offset: offset,
            blur: blur,
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.30)
        )
    }

    private static func drawScreenshot(
        _ screenshot: CGImage,
        selectionPx: CGRect,
        dest: CGRect,
        cornerRadii: SelectionCornerRadii,
        in ctx: CGContext
    ) {
        guard !selectionPx.isNull, !selectionPx.isEmpty,
              let cropped = screenshot.cropping(to: selectionPx) else { return }
        // CGContextDrawImage renders upside-down in a y-flipped context. Locally
        // re-flip around the destination rect so the screenshot stays upright.
        ctx.saveGState()
        let radii = cornerRadii.clamped(to: dest.size)
        if !radii.isZero {
            ctx.addPath(radii.path(in: dest))
            ctx.clip()
        }
        ctx.translateBy(x: dest.minX, y: dest.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cropped, in: CGRect(origin: .zero, size: dest.size))
        ctx.restoreGState()
    }
}
