import AppKit
import Foundation

struct DOMCaptureRect: Codable, Sendable, Equatable {
    let left: Double
    let top: Double
    let width: Double
    let height: Double

    var area: Double {
        width * height
    }
}

struct DOMCaptureViewport: Codable, Sendable, Equatable {
    let width: Double
    let height: Double
    let devicePixelRatio: Double
    let scrollX: Double
    let scrollY: Double
}

struct DOMCandidateSnapshot: Codable, Identifiable, Sendable, Equatable {
    let id: Int
    let rect: DOMCaptureRect
    let depth: Int
    let label: String
    let tagName: String
    let role: String?
    let preview: Bool
    let selected: Bool
}

struct DOMCaptureSessionRequest: Decodable, Sendable {
    let screenshotBase64: String
    let selectedRect: DOMCaptureRect
    let viewport: DOMCaptureViewport
    let candidates: [DOMCandidateSnapshot]
    let selectedIndex: Int
    let pageTitle: String?
    let pageURL: String?
    let imageWidth: Double?
    let imageHeight: Double?
}

struct DOMCaptureSession: Identifiable {
    let id = UUID()
    let screenshotData: Data
    let screenshotImage: NSImage
    let selectedRect: DOMCaptureRect
    let viewport: DOMCaptureViewport
    let candidates: [DOMCandidateSnapshot]
    let selectedIndex: Int
    let pageTitle: String
    let pageURL: String
    let imagePixelSize: CGSize
    let capturedAt: Date

    init(request: DOMCaptureSessionRequest) throws {
        let base64 = request.screenshotBase64
            .replacingOccurrences(of: "data:image/png;base64,", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              !data.isEmpty,
              let image = NSImage(data: data) else {
            throw DOMCaptureSessionError.invalidScreenshot
        }

        screenshotData = data
        screenshotImage = image
        selectedRect = request.selectedRect
        viewport = request.viewport
        candidates = request.candidates
        selectedIndex = request.selectedIndex
        pageTitle = request.pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled Page"
        pageURL = request.pageURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? ""

        if let width = request.imageWidth,
           let height = request.imageHeight,
           width > 0,
           height > 0 {
            imagePixelSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        } else if let rep = NSBitmapImageRep(data: data) {
            imagePixelSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        } else {
            imagePixelSize = image.size
        }

        capturedAt = Date()
    }

    func selectedCropPNGData() -> Data? {
        guard let rep = NSBitmapImageRep(data: screenshotData),
              let cgImage = rep.cgImage else {
            return nil
        }

        let cropRect = pixelRect(for: selectedRect, pixelSize: CGSize(width: cgImage.width, height: cgImage.height))
            .integral

        guard cropRect.width >= 1,
              cropRect.height >= 1,
              let croppedImage = cgImage.cropping(to: cropRect) else {
            return nil
        }

        return NSBitmapImageRep(cgImage: croppedImage).representation(using: .png, properties: [:])
    }

    func pixelRect(for rect: DOMCaptureRect, pixelSize: CGSize? = nil) -> CGRect {
        let targetSize = pixelSize ?? imagePixelSize
        let scaleX = targetSize.width / max(1, CGFloat(viewport.width))
        let scaleY = targetSize.height / max(1, CGFloat(viewport.height))

        let x = max(0, CGFloat(rect.left) * scaleX)
        let y = max(0, CGFloat(rect.top) * scaleY)
        let width = max(1, min(targetSize.width - x, CGFloat(rect.width) * scaleX))
        let height = max(1, min(targetSize.height - y, CGFloat(rect.height) * scaleY))

        return CGRect(x: x, y: y, width: width, height: height)
    }
}

@MainActor
final class DOMCaptureSessionStore: ObservableObject {
    @Published var session: DOMCaptureSession?
}

enum DOMCaptureSessionError: Error {
    case invalidScreenshot
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
