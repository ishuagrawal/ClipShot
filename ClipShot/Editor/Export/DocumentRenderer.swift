import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// Pure, deterministic flattener of the export crop. The in-place canvas preview
/// reuses this output so Copy/Save and preview stay identical.
enum DocumentRenderer {

    static func dynamicBackgroundImage(for screenshot: CGImage, selection: CGRect) -> CGImage? {
        DynamicMeshCache.shared.meshImage(for: screenshot, selection: selection)
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
            drawDocumentBackground(doc, in: ctx, outputRect: outputRect)
        }
        if !doc.padding.isZero {
            drawScreenshotShadow(
                doc.shadow,
                dest: dest,
                cornerRadii: doc.effectiveSelectionCornerRadii,
                outputRect: outputRect,
                in: ctx
            )
        }
        drawScreenshot(
            doc.screenshot,
            selectionPx: selectionPx,
            dest: dest,
            cornerRadii: doc.effectiveSelectionCornerRadii,
            in: ctx
        )
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
            case .line(let from, let to, let color, let weight, let dash):
                drawLine(from: from, to: to, color: color, weight: weight, dash: dash, in: ctx)
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

    private static func drawLine(
        from: CGPoint,
        to: CGPoint,
        color: CGColor,
        weight: CGFloat,
        dash: Annotation.LineDash,
        in ctx: CGContext
    ) {
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(weight)
        let style = AnnotationGeometry.dashStyle(dash, weight: weight)
        ctx.setLineCap(style.cap)
        if let pattern = style.pattern {
            ctx.setLineDash(phase: 0, lengths: pattern)
        }
        ctx.addPath(AnnotationGeometry.linePath(from: from, to: to))
        ctx.strokePath()
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
        guard let mesh = DynamicMeshCache.shared.meshImage(for: screenshot, selection: selection) else { return }
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

    private static func drawScreenshotShadow(
        _ shadow: ShadowConfig,
        dest: CGRect,
        cornerRadii: SelectionCornerRadii,
        outputRect: CGRect,
        in ctx: CGContext
    ) {
        guard let image = screenshotShadowImage(
            shadow,
            dest: dest,
            cornerRadii: cornerRadii,
            outputSize: outputRect.size
        ) else { return }
        drawTopLeftImage(image, in: ctx, outputRect: outputRect)
    }

    /// Renders only the pixels outside the screenshot shape. Drawing the shadow
    /// in a temporary bitmap avoids clipping it when the screenshot itself is
    /// subsequently masked to rounded corners.
    private static func screenshotShadowImage(
        _ config: ShadowConfig,
        dest: CGRect,
        cornerRadii: SelectionCornerRadii,
        outputSize: CGSize
    ) -> CGImage? {
        let shadow = config.clamped
        guard shadow.isEnabled, shadow.opacity > 0 else { return nil }
        let width = Int(outputSize.width)
        let height = Int(outputSize.height)
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

        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        let color = shadow.color.copy(alpha: shadow.opacity)
            ?? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: shadow.opacity)
        ctx.setShadow(
            offset: CGSize(width: shadow.offsetX, height: -shadow.offsetY),
            blur: shadow.blur,
            color: color
        )
        let path = screenshotPath(dest: dest, cornerRadii: cornerRadii)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.addPath(path)
        ctx.fillPath()

        // Remove the opaque shape that cast the shadow, leaving shadow pixels only.
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setBlendMode(.clear)
        ctx.addPath(path)
        ctx.fillPath()
        return ctx.makeImage()
    }

    // MARK: - Background composition (blur + noise)

    private static let ciContext = CIContext(options: nil)

    /// Draws the document's background into the (already card-clipped) context,
    /// using the composed blur+noise image when effects are active, else the
    /// plain style fill.
    private static func drawDocumentBackground(
        _ doc: EditorDocument,
        in ctx: CGContext,
        outputRect: CGRect
    ) {
        if doc.backgroundEffects.isActive, doc.background.kind != .none,
           let composed = composedBackgroundImage(for: doc) {
            drawTopLeftImage(composed, in: ctx, outputRect: outputRect)
        } else {
            drawBackground(doc.background, in: ctx, outputRect: outputRect,
                           screenshot: doc.screenshot, selection: doc.baseSelection)
        }
    }

    /// Full-crop background image with blur + noise baked in (top-left oriented).
    /// Returns the plain base when no effect is active. Used by both export and
    /// the live canvas so the two stay pixel-identical.
    static func composedBackgroundImage(for doc: EditorDocument) -> CGImage? {
        let size = doc.effectiveCrop.integral.size
        guard let base = baseBackgroundImage(doc, size: size) else { return nil }
        let fx = doc.backgroundEffects.clamped
        guard fx.isActive else { return base }

        var image = CIImage(cgImage: base)
        let extent = image.extent
        if fx.noiseOpacity > 0 {
            image = applyingLuminanceNoise(to: image, strength: fx.noiseOpacity, extent: extent)
        }
        if fx.blurRadius > 0 {
            image = image.clampedToExtent()
                .applyingGaussianBlur(sigma: Double(fx.blurRadius))
                .cropped(to: extent)
        }
        return ciContext.createCGImage(image, from: extent) ?? base
    }

    /// Rasterizes the plain style fill at crop size. Replicates render()'s y-down
    /// top-left space so the dynamic mesh (and gradients) draw upright/identically.
    private static func baseBackgroundImage(_ doc: EditorDocument, size: CGSize) -> CGImage? {
        let width = Int(size.width), height = Int(size.height)
        guard width > 0, height > 0 else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        drawBackground(doc.background, in: ctx,
                       outputRect: CGRect(origin: .zero, size: size),
                       screenshot: doc.screenshot, selection: doc.baseSelection)
        return ctx.makeImage()
    }

    /// Blends monochrome grain through neutral soft light. Mid-grey is a no-op,
    /// so the texture changes local brightness without washing the background
    /// toward grey or adding a color cast.
    private static func applyingLuminanceNoise(
        to image: CIImage,
        strength: CGFloat,
        extent: CGRect
    ) -> CIImage {
        let noise = CIFilter(name: "CIRandomGenerator")?.outputImage
            ?? CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
        let mono = noise.applyingFilter("CIColorControls", parameters: ["inputSaturation": 0])
        let grain = mono.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: Double(strength))
        ]).cropped(to: extent)
        return grain
            .applyingFilter("CISoftLightBlendMode", parameters: [
                kCIInputBackgroundImageKey: image
            ])
            .cropped(to: extent)
    }

    private static func drawTopLeftImage(
        _ image: CGImage,
        in ctx: CGContext,
        outputRect: CGRect
    ) {
        ctx.saveGState()
        ctx.clip(to: outputRect)
        ctx.translateBy(x: outputRect.minX, y: outputRect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: outputRect.size))
        ctx.restoreGState()
    }

    private static func screenshotPath(
        dest: CGRect,
        cornerRadii: SelectionCornerRadii
    ) -> CGPath {
        let radii = cornerRadii.clamped(to: dest.size)
        return radii.isZero ? CGPath(rect: dest, transform: nil) : radii.path(in: dest)
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
            ctx.addPath(screenshotPath(dest: dest, cornerRadii: radii))
            ctx.clip()
        }
        ctx.translateBy(x: dest.minX, y: dest.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cropped, in: CGRect(origin: .zero, size: dest.size))
        ctx.restoreGState()
    }
}
