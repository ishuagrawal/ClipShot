import AppKit
import CoreGraphics

@MainActor
final class ScreenCaptureService {
    func copyPNGToClipboard(axFrame: CGRect) -> Bool {
        copyPNGToClipboard(screenFrame: axFrame)
    }

    func copyPNGToClipboard(screenFrame: CGRect) -> Bool {
        let rect = screenFrame.integral
        guard rect.width > 0, rect.height > 0 else {
            return false
        }

        guard let image = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            return false
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }

        return copyPNGDataToClipboard(pngData)
    }

    func copyPNGDataToClipboard(_ pngData: Data) -> Bool {
        guard !pngData.isEmpty else {
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
        return true
    }
}
