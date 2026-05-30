import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// Pure, deterministic flattener of the export crop. The in-place canvas preview
/// reuses this output so Copy/Save and preview stay identical.
enum DocumentRenderer {

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

        drawBackground(doc.background, in: ctx, outputRect: outputRect, screenshot: doc.screenshot)
        drawScreenshot(doc.screenshot, selectionPx: selectionPx, dest: dest, in: ctx)
        drawAnnotations(doc.annotations, in: ctx)

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
        screenshot: CGImage
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
        case .blurExtend(let radius):
            drawBlurExtend(radius: radius, in: ctx, outputRect: outputRect, screenshot: screenshot)
        }
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

    private static func drawBlurExtend(
        radius: CGFloat,
        in ctx: CGContext,
        outputRect: CGRect,
        screenshot: CGImage
    ) {
        let blurred = BlurExtendCache.shared.blurredImage(for: screenshot, radius: radius) ?? screenshot
        let fill = aspectFillRect(
            imageSize: CGSize(width: blurred.width, height: blurred.height),
            into: outputRect
        )
        ctx.saveGState()
        ctx.clip(to: outputRect)
        ctx.translateBy(x: fill.minX, y: fill.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(blurred, in: CGRect(origin: .zero, size: fill.size))
        ctx.restoreGState()
    }

    private static func aspectFillRect(imageSize: CGSize, into rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }

    private static func drawScreenshot(
        _ screenshot: CGImage,
        selectionPx: CGRect,
        dest: CGRect,
        in ctx: CGContext
    ) {
        guard !selectionPx.isNull, !selectionPx.isEmpty,
              let cropped = screenshot.cropping(to: selectionPx) else { return }
        // CGContextDrawImage renders upside-down in a y-flipped context. Locally
        // re-flip around the destination rect so the screenshot stays upright.
        ctx.saveGState()
        ctx.translateBy(x: dest.minX, y: dest.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cropped, in: CGRect(origin: .zero, size: dest.size))
        ctx.restoreGState()
    }
}

private final class BlurExtendCache: @unchecked Sendable {
    static let shared = BlurExtendCache()

    private let lock = NSLock()
    private var cachedImage: CGImage?
    private var cachedSource: CGImage?
    private var cachedRadius: CGFloat = -1
    private var cachedWidth = -1
    private var cachedHeight = -1
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func blurredImage(for source: CGImage, radius: CGFloat) -> CGImage? {
        lock.lock()
        if let cachedImage,
           let cachedSource,
           cachedSource === source,
           cachedRadius == radius,
           cachedWidth == source.width,
           cachedHeight == source.height {
            lock.unlock()
            return cachedImage
        }
        lock.unlock()

        let input = CIImage(cgImage: source)
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
        let rect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        guard let result = ciContext.createCGImage(input, from: rect) else { return nil }

        lock.lock()
        cachedImage = result
        cachedSource = source
        cachedRadius = radius
        cachedWidth = source.width
        cachedHeight = source.height
        lock.unlock()
        return result
    }
}
