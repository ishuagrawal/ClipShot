import AppKit
import Foundation
@testable import ClipShot

enum FixtureDocument {
    /// Builds a `CaptureSession` AND a matching `EditorDocument` from a recognizable
    /// programmatic screenshot. Selection covers a contrasting inner region so cropping
    /// behavior is visually verifiable from pixel buffers alone.
    static func basicPair() -> (session: CaptureSession, document: EditorDocument) {
        let viewport = CGSize(width: 400, height: 300)
        let cgImage = makeStripedImage(size: viewport)
        let pngData = NSBitmapImageRep(cgImage: cgImage)
            .representation(using: .png, properties: [:])!

        // CaptureSessionRequest is Decodable-only; construct via JSON decoding.
        let selectedRect = CaptureRect(left: 80, top: 60, width: 120, height: 90)
        let viewportObj = CaptureViewport(
            width: Double(viewport.width),
            height: Double(viewport.height),
            devicePixelRatio: 1,
            scrollX: 0,
            scrollY: 0
        )

        // Build JSON to decode into CaptureSessionRequest.
        let json: [String: Any] = [
            "screenshotBase64": pngData.base64EncodedString(),
            "selectedRect": [
                "left": selectedRect.left,
                "top": selectedRect.top,
                "width": selectedRect.width,
                "height": selectedRect.height
            ],
            "viewport": [
                "width": viewportObj.width,
                "height": viewportObj.height,
                "devicePixelRatio": viewportObj.devicePixelRatio,
                "scrollX": viewportObj.scrollX,
                "scrollY": viewportObj.scrollY
            ],
            "candidates": [],
            "selectedIndex": 0,
            "sourceTitle": "Fixture",
            "sourceURL": "https://example.com",
            "imageWidth": Double(viewport.width),
            "imageHeight": Double(viewport.height)
        ]
        let jsonData = try! JSONSerialization.data(withJSONObject: json)
        let request = try! JSONDecoder().decode(CaptureSessionRequest.self, from: jsonData)
        let session = try! CaptureSession(request: request)

        let pixelSelection = session.pixelRect(for: request.selectedRect)
        let document = EditorDocument(
            screenshot: cgImage,
            viewport: viewport,
            sourceTitle: "Fixture",
            sourceURL: "https://example.com",
            baseSelection: pixelSelection
        )
        return (session, document)
    }

    static func makeSolidImage(color: CGColor, size: CGSize) -> CGImage {
        let w = Int(size.width), h = Int(size.height)
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    /// Top-left, top-right, bottom-left, bottom-right quadrant colors.
    /// Note: CGContext origin is bottom-left, so "top" quadrants are the upper half.
    static func makeQuadrantImage(tl: CGColor, tr: CGColor, bl: CGColor, br: CGColor,
                                  size: CGSize) -> CGImage {
        let w = Int(size.width), h = Int(size.height)
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let halfW = CGFloat(w) / 2, halfH = CGFloat(h) / 2
        ctx.setFillColor(bl); ctx.fill(CGRect(x: 0, y: 0, width: halfW, height: halfH))
        ctx.setFillColor(br); ctx.fill(CGRect(x: halfW, y: 0, width: halfW, height: halfH))
        ctx.setFillColor(tl); ctx.fill(CGRect(x: 0, y: halfH, width: halfW, height: halfH))
        ctx.setFillColor(tr); ctx.fill(CGRect(x: halfW, y: halfH, width: halfW, height: halfH))
        return ctx.makeImage()!
    }

    /// Diagonal red/blue stripes — every pixel deterministic from coordinates, so any
    /// offset/scale/flip bug is immediately visible in a pixel comparison.
    static func makeStripedImage(size: CGSize) -> CGImage {
        let w = Int(size.width)
        let h = Int(size.height)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        for y in 0..<h {
            for x in 0..<w {
                let isRed = ((x + y) / 8) % 2 == 0
                ctx.setFillColor(
                    isRed
                    ? CGColor(red: 1, green: 0, blue: 0, alpha: 1)
                    : CGColor(red: 0, green: 0, blue: 1, alpha: 1)
                )
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return ctx.makeImage()!
    }
}
