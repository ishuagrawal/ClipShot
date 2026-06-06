import AppKit
import CoreGraphics
import ScreenCaptureKit

struct NativeCaptureBitmap: @unchecked Sendable {
    let image: CGImage
    let pixelScale: CGFloat
}

struct NativeWindowMatch: Equatable, Sendable {
    let index: Int
    let score: CGFloat
    let windowCoverage: CGFloat
    let regionCoverage: CGFloat
    let area: CGFloat
}

struct NativeWindowShot: @unchecked Sendable {
    let image: CGImage
    let pixelScale: CGFloat
    let appName: String
    /// Rounded corners are baked into the image's alpha channel for window
    /// captures, so this stays nil for them; it carries radii only for capture
    /// paths (DOM/web) that hand back a rectangular bitmap.
    let cornerRadii: DOMCornerRadii?
}

enum NativeWindowMatcher {
    static func bestMatch(frames: [CGRect],
                          in region: CGRect,
                          minSide: CGFloat = 80,
                          minWindowCoverage: CGFloat = 0.90,
                          minRegionCoverage: CGFloat = 0.50,
                          edgeTolerance: CGFloat = 24) -> NativeWindowMatch? {
        rankedMatches(
            frames: frames,
            in: region,
            maxResults: 1,
            minSide: minSide,
            minWindowCoverage: minWindowCoverage,
            minRegionCoverage: minRegionCoverage,
            edgeTolerance: edgeTolerance
        ).first
    }

    static func rankedMatches(frames: [CGRect],
                              in region: CGRect,
                              maxResults: Int = 3,
                              minSide: CGFloat = 80,
                              minWindowCoverage: CGFloat = 0.90,
                              minRegionCoverage: CGFloat = 0.50,
                              edgeTolerance: CGFloat = 24) -> [NativeWindowMatch] {
        let regionArea = area(region)
        guard regionArea > 0 else { return [] }

        let tolerantRegion = region.insetBy(
            dx: -max(0, edgeTolerance),
            dy: -max(0, edgeTolerance)
        )

        let matches = frames.enumerated().compactMap { index, frame -> NativeWindowMatch? in
            guard frame.width >= minSide, frame.height >= minSide else { return nil }
            let windowArea = area(frame)
            guard windowArea > 0 else { return nil }

            let intersection = frame.intersection(region)
            guard !intersection.isNull, !intersection.isEmpty else { return nil }

            let tolerantIntersection = frame.intersection(tolerantRegion)
            guard !tolerantIntersection.isNull, !tolerantIntersection.isEmpty else { return nil }

            let intersectionArea = area(intersection)
            let windowCoverage = area(tolerantIntersection) / windowArea
            let regionCoverage = intersectionArea / regionArea
            guard windowCoverage >= minWindowCoverage,
                  regionCoverage >= minRegionCoverage else { return nil }

            return NativeWindowMatch(
                index: index,
                score: windowCoverage * regionCoverage,
                windowCoverage: windowCoverage,
                regionCoverage: regionCoverage,
                area: windowArea
            )
        }

        return matches
            .sorted {
                if abs($0.score - $1.score) > 0.02 { return $0.score > $1.score }
                if abs($0.area - $1.area) > 1 { return $0.area > $1.area }
                return $0.index < $1.index
            }
            .prefix(maxResults)
            .map { $0 }
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        max(0, rect.width) * max(0, rect.height)
    }
}

enum NativeCaptureError: Error {
    case noDisplay
    case captureFailed
}

@MainActor
final class NativeScreenCapturer: @unchecked Sendable {
    func capture(region: NativeCaptureRegion) async throws -> NativeWindowShot {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first(where: { $0.displayID == region.displayID })
            ?? content.displays.first else {
            throw NativeCaptureError.noDisplay
        }

        let scale = backingScale(forDisplayID: display.displayID)
        let regionGlobal = region.sourceRect.offsetBy(dx: display.frame.minX, dy: display.frame.minY)

        if let matchedWindow = leadingWindow(regionGlobal: regionGlobal, windows: content.windows) {
            return try await captureWindow(matchedWindow, display: display, scale: scale)
        }

        let bitmap = try await captureBitmap(region: region, display: display, scale: scale)
        return NativeWindowShot(
            image: bitmap.image,
            pixelScale: bitmap.pixelScale,
            appName: "Screen",
            cornerRadii: nil
        )
    }

    /// Capture a single window in isolation.
    ///
    /// We deliberately use `CGWindowListCreateImage` rather than
    /// ScreenCaptureKit here. SCK's `desktopIndependentWindow` filter bakes the
    /// window's rounded corners with a hard, aliased mask and composites the
    /// result premultiplied, so the corner edges come back jagged and the square
    /// content under the corner is already gone — there is nothing left to
    /// re-smooth. `CGWindowListCreateImage` is the same path `screencapture`
    /// uses: it returns the window with the system's *antialiased* rounded
    /// corners, a real alpha channel, and exact bounds (shadow excluded via
    /// `boundsIgnoreFraming`, so no background bleed or leading-edge slivers).
    /// It is deprecated but still functional and remains the only API that hands
    /// back smooth window corners.
    private func captureWindow(_ window: SCWindow,
                               display: SCDisplay,
                               scale: CGFloat) async throws -> NativeWindowShot {
        let options: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        guard let windowShape = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            window.windowID,
            options
        ) else {
            throw NativeCaptureError.captureFailed
        }

        let pixelScale = window.frame.width > 0 && window.frame.height > 0
            ? max(
                CGFloat(windowShape.width) / window.frame.width,
                CGFloat(windowShape.height) / window.frame.height
            )
            : scale
        let windowRegion = NativeCaptureRegion(
            displayID: display.displayID,
            sourceRect: displayLocalRect(for: window.frame, display: display)
        )
        let visibleBitmap = try await captureBitmap(
            region: windowRegion,
            display: display,
            scale: pixelScale,
            outputPixelSize: CGSize(width: windowShape.width, height: windowShape.height)
        )

        return NativeWindowShot(
            image: shapedWindowImage(visibleBitmap.image, windowShape: windowShape),
            pixelScale: max(1, pixelScale),
            appName: window.owningApplication?.applicationName ?? "Window",
            cornerRadii: nil
        )
    }

    /// Round the corners of the opaque on-screen color crop using a clean,
    /// antialiased vector mask.
    ///
    /// We take color from the on-screen crop (`visibleImage`) because that is the
    /// only source that shows translucent window materials filled with the
    /// blurred backdrop the user actually sees — `CGWindowListCreateImage`'s own
    /// pixels are partly transparent there and wash out over the editor
    /// background. The catch is that on-screen, the rounded-corner boundary
    /// pixels are a physical blend of window edge and desktop behind it. So
    /// rather than reuse the shape capture's alpha (which would drag that blended
    /// fringe in and read as aliasing), we only *measure* the radius from the
    /// shape, then clip with our own path inset by 1px — the antialiased edge
    /// then samples window interior, never the window/desktop seam.
    private func shapedWindowImage(_ visibleImage: CGImage, windowShape: CGImage) -> CGImage {
        let width = visibleImage.width
        let height = visibleImage.height
        guard width > 0, height > 0 else { return visibleImage }

        let radii = cornerRadiiPixels(in: windowShape)
        guard !radii.isZero else { return visibleImage }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return visibleImage }

        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        // Inset by 1px so the antialiased clip edge samples window interior, not
        // the on-screen window/desktop seam. Pull each radius in by the same 1px
        // so the corner arc stays centered on the true window corner.
        let inset: CGFloat = 1
        let maskRect = rect.insetBy(dx: inset, dy: inset)
        func shrink(_ size: CGSize) -> CGSize {
            CGSize(width: max(0, size.width - inset), height: max(0, size.height - inset))
        }
        let adjusted = SelectionCornerRadii(
            topLeft: shrink(radii.topLeft),
            topRight: shrink(radii.topRight),
            bottomRight: shrink(radii.bottomRight),
            bottomLeft: shrink(radii.bottomLeft)
        )
        context.addPath(adjusted.path(in: maskRect))
        context.clip()
        context.draw(visibleImage, in: rect)
        return context.makeImage() ?? visibleImage
    }

    /// Measure each corner's radius (sub-pixel, in pixels) from the shape
    /// capture's alpha channel, independently — averaging the four into one
    /// radius left one corner visibly off.
    ///
    /// We sample along the diagonal heading inward from each corner rather than
    /// along an edge row/column: a straight edge is itself antialiased (~50%
    /// alpha), which muddies an edge-wise scan, whereas the diagonal stays fully
    /// transparent until it punches through the corner arc. For a quarter circle
    /// of radius `r`, the diagonal crosses the arc at distance `t = r·(1−1/√2)`
    /// from the corner, so `r = t / (1−1/√2)`.
    private func cornerRadiiPixels(in shape: CGImage) -> SelectionCornerRadii {
        let width = shape.width
        let height = shape.height
        guard width > 16, height > 16 else { return .zero }

        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return .zero }
        context.draw(shape, in: CGRect(x: 0, y: 0, width: width, height: height))

        func alpha(_ x: Int, _ y: Int) -> Int { Int(data[y * bytesPerRow + x * 4 + 3]) }

        let diagonalFactor = 1 - 1 / 2.0.squareRoot()
        let limit = min(width, height) / 2

        func radius(cornerX: Int, cornerY: Int, stepX: Int, stepY: Int) -> CGFloat {
            var previous = alpha(cornerX, cornerY)
            for step in 1..<limit {
                let value = alpha(cornerX + stepX * step, cornerY + stepY * step)
                if value >= 128 {
                    let delta = value - previous
                    let fraction = delta > 0 ? CGFloat(128 - previous) / CGFloat(delta) : 0
                    let crossing = CGFloat(step - 1) + fraction
                    return crossing / CGFloat(diagonalFactor)
                }
                previous = value
            }
            return 0
        }

        func uniform(_ r: CGFloat) -> CGSize { CGSize(width: r, height: r) }

        return SelectionCornerRadii(
            topLeft: uniform(radius(cornerX: 0, cornerY: 0, stepX: 1, stepY: 1)),
            topRight: uniform(radius(cornerX: width - 1, cornerY: 0, stepX: -1, stepY: 1)),
            bottomRight: uniform(radius(cornerX: width - 1, cornerY: height - 1, stepX: -1, stepY: -1)),
            bottomLeft: uniform(radius(cornerX: 0, cornerY: height - 1, stepX: 1, stepY: -1))
        )
    }

    private func captureBitmap(region: NativeCaptureRegion,
                               display: SCDisplay,
                               scale: CGFloat,
                               outputPixelSize: CGSize? = nil) async throws -> NativeCaptureBitmap {
        let config = SCStreamConfiguration()
        config.sourceRect = region.sourceRect
        config.width = max(1, Int((outputPixelSize?.width ?? region.sourceRect.width * scale).rounded()))
        config.height = max(1, Int((outputPixelSize?.height ?? region.sourceRect.height * scale).rounded()))
        config.scalesToFit = false
        config.showsCursor = false
        if #available(macOS 14.0, *) {
            config.captureResolution = .best
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        return NativeCaptureBitmap(image: image, pixelScale: scale)
    }

    private func displayLocalRect(for globalRect: CGRect, display: SCDisplay) -> CGRect {
        globalRect
            .intersection(display.frame)
            .offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
    }

    private func leadingWindow(regionGlobal: CGRect,
                               windows: [SCWindow]) -> SCWindow? {
        let eligible = windows.filter { window in
            let frame = window.frame
            return window.isOnScreen
                && window.windowLayer == 0
                && frame.width > 0
                && frame.height > 0
                && window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
        }
        guard let match = NativeWindowMatcher.bestMatch(
            frames: eligible.map(\.frame),
            in: regionGlobal
        ) else { return nil }

        return eligible[match.index]
    }

    private func backingScale(forDisplayID displayID: CGDirectDisplayID) -> CGFloat {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let screen = NSScreen.screens.first {
            guard let number = $0.deviceDescription[key] as? NSNumber else { return false }
            return CGDirectDisplayID(number.uint32Value) == displayID
        }
        return screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }
}

@MainActor
final class NativeCaptureLauncher {
    private let coordinator: CaptureCoordinator
    private let appState: AppState
    private let overlay = NativeCaptureRegionOverlay()
    private let capturer = NativeScreenCapturer()

    init(coordinator: CaptureCoordinator, appState: AppState) {
        self.coordinator = coordinator
        self.appState = appState
    }

    func beginCapture() {
        appState.setCaptureStatus("Drag to capture")
        closeTransientClipShotWindows()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.overlay.present { [weak self] region in
                guard let self else { return }
                guard let region else {
                    self.appState.setCaptureStatus(nil)
                    return
                }
                Task { await self.capture(region: region) }
            }
        }
    }

    private func closeTransientClipShotWindows() {
        for window in NSApp.windows where window.isVisible {
            window.orderOut(nil)
        }
    }

    private func capture(region: NativeCaptureRegion) async {
        do {
            appState.setCaptureStatus("Capturing screenshot...")
            let shot = try await capturer.capture(region: region)
            guard coordinator.openNativeScreenshot(
                image: shot.image,
                pixelScale: shot.pixelScale,
                sourceAppName: shot.appName,
                cornerRadii: shot.cornerRadii
            ) else {
                throw NativeCaptureError.captureFailed
            }
        } catch {
            appState.setCaptureStatus("Capture failed")
            NSSound.beep()
        }
    }
}
