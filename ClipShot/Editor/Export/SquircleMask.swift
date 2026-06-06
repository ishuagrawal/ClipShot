import CoreGraphics
import QuartzCore

/// Renders a uniform continuous-corner (system squircle) rounded rectangle as a
/// white-inside / black-outside grayscale mask, matching macOS window corners.
/// Supersampled then downscaled because CALayer corner antialiasing is crude at 1x.
enum SquircleMask {
    static func make(width: Int, height: Int, radius: CGFloat) -> CGImage? {
        guard width > 0, height > 0, radius > 0.5 else { return nil }

        let pixelCount = max(1, width * height)
        let maxSupersampledPixels = 32_000_000
        let affordable = Int(
            (Double(maxSupersampledPixels) / Double(pixelCount)).squareRoot().rounded(.down)
        )
        let sampling = max(1, min(4, affordable))
        let bigWidth = width * sampling
        let bigHeight = height * sampling
        let gray = CGColorSpaceCreateDeviceGray()
        let info = CGImageAlphaInfo.none.rawValue

        guard let bigContext = CGContext(
            data: nil, width: bigWidth, height: bigHeight,
            bitsPerComponent: 8, bytesPerRow: 0, space: gray, bitmapInfo: info
        ) else { return nil }

        let containerLayer = CALayer()
        containerLayer.bounds = CGRect(x: 0, y: 0, width: bigWidth, height: bigHeight)
        let roundedLayer = CALayer()
        roundedLayer.frame = containerLayer.bounds
        roundedLayer.backgroundColor = CGColor(gray: 1, alpha: 1)
        roundedLayer.cornerRadius = min(
            radius * CGFloat(sampling),
            CGFloat(min(bigWidth, bigHeight)) / 2
        )
        roundedLayer.cornerCurve = .continuous
        roundedLayer.masksToBounds = true
        roundedLayer.allowsEdgeAntialiasing = true
        containerLayer.addSublayer(roundedLayer)
        containerLayer.render(in: bigContext)
        guard let bigImage = bigContext.makeImage() else { return nil }

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: gray, bitmapInfo: info
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(bigImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
