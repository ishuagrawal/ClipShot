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
    /// The measured radius of the baked rounded corners, so concentric padding
    /// can match it. nil when no rounding was detected, or for non-window
    /// rectangular captures.
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

enum NativeScreencaptureCLI {
    /// Format a global, top-left-origin point rect as the system `screencapture`
    /// tool's `-R x,y,w,h` argument. Whole points; the tool renders at the
    /// display's native pixel scale (2x on Retina).
    static func rectArgument(for rect: CGRect) -> String {
        "\(Int(rect.minX.rounded())),\(Int(rect.minY.rounded())),"
            + "\(Int(rect.width.rounded())),\(Int(rect.height.rounded()))"
    }
}

enum NativeWindowShaping {
    /// Convert a corner radius measured in the shape capture's pixel grid into the
    /// color capture's pixel grid. The two share a scale on uniform-DPI displays
    /// (→ unchanged), but the `screencapture` color crop and the
    /// `CGWindowListCreateImage` shape can round to dimensions that differ by a
    /// pixel; rescaling keeps the rounded mask aligned to the color image.
    static func cornerRadius(shapeRadius: CGFloat,
                             shapeSize: CGSize,
                             colorSize: CGSize) -> CGFloat {
        guard shapeRadius > 0, shapeSize.width > 0, shapeSize.height > 0 else { return shapeRadius }
        return shapeRadius * min(
            colorSize.width / shapeSize.width,
            colorSize.height / shapeSize.height
        )
    }
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

        switch region.kind {
        case .windowAtPoint:
            guard let window = window(at: regionGlobal.origin, windows: content.windows) else {
                throw NativeCaptureError.captureFailed
            }
            return try await captureWindow(window, display: display, scale: scale)

        case .rect:
            if let matchedWindow = leadingWindow(regionGlobal: regionGlobal, windows: content.windows) {
                return try await captureWindow(matchedWindow, display: display, scale: scale)
            }
            // Prefer the system `screencapture` tool (same path Apple's own
            // screenshots use): true native pixels with none of the resampling
            // softness ScreenCaptureKit applies to a cropped `sourceRect`. Fall
            // back to the SCK bitmap path if it fails (sandbox/permission/tooling).
            let bitmap: NativeCaptureBitmap
            if let native = await captureNativeRect(globalRect: regionGlobal) {
                bitmap = native
            } else {
                bitmap = try await captureBitmap(region: region, display: display, scale: scale)
            }
            return NativeWindowShot(
                image: bitmap.image,
                pixelScale: bitmap.pixelScale,
                appName: "Screen",
                cornerRadii: nil
            )
        }
    }

    /// Capture a global screen rect at native resolution via `/usr/sbin/screencapture`.
    /// The tool writes a device-native PNG (2x on Retina) identical in fidelity to a
    /// system screenshot — sharper than a ScreenCaptureKit cropped capture, which
    /// resamples. Runs off the main actor; returns nil on any failure so the caller
    /// can fall back to the SCK path. Requires Screen Recording permission, which the
    /// app already holds for SCK.
    private func captureNativeRect(globalRect: CGRect) async -> NativeCaptureBitmap? {
        guard globalRect.width >= 1, globalRect.height >= 1 else { return nil }
        let path = NSTemporaryDirectory() + "clipshot_capture_\(UUID().uuidString).png"
        let rectArg = "-R" + NativeScreencaptureCLI.rectArgument(for: globalRect)

        let succeeded: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = [rectArg, "-x", "-t", "png", path]
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }

        defer { try? FileManager.default.removeItem(atPath: path) }
        guard succeeded,
              let data = FileManager.default.contents(atPath: path),
              let image = NSBitmapImageRep(data: data)?.cgImage else {
            return nil
        }

        let scale = globalRect.width > 0 ? CGFloat(image.width) / globalRect.width : 1
        return NativeCaptureBitmap(image: image, pixelScale: max(1, scale))
    }

    /// Frontmost eligible window containing a global point (SCShareableContent
    /// returns windows front-to-back, so the first hit is topmost).
    private func window(at point: CGPoint, windows: [SCWindow]) -> SCWindow? {
        windows.first { window in
            window.isOnScreen
                && window.windowLayer == 0
                && window.frame.contains(point)
                && window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
        }
    }

    /// Capture a single window in isolation via `CGWindowListCreateImage` (the
    /// `screencapture` path): smooth antialiased corners, real alpha, exact
    /// bounds, no shadow/bleed. SCK's `desktopIndependentWindow` instead bakes
    /// jagged corners and discards the under-corner content. Deprecated but the
    /// only API returning smooth window corners.
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

        // Color crop at native fidelity. Prefer `screencapture` (sharp, like the
        // system screenshot); fall back to the SCK bitmap forced onto the shape's
        // pixel grid. `windowShape` supplies only the rounded-corner alpha.
        let visibleBitmap: NativeCaptureBitmap
        if let native = await captureNativeRect(globalRect: window.frame) {
            visibleBitmap = native
        } else {
            let windowRegion = NativeCaptureRegion(
                displayID: display.displayID,
                sourceRect: displayLocalRect(for: window.frame, display: display)
            )
            visibleBitmap = try await captureBitmap(
                region: windowRegion,
                display: display,
                scale: scale,
                outputPixelSize: CGSize(width: windowShape.width, height: windowShape.height)
            )
        }

        let shaped = shapedWindowImage(
            visibleBitmap.image,
            windowShape: windowShape,
            pixelScale: visibleBitmap.pixelScale
        )
        let safeScale = max(1, visibleBitmap.pixelScale)
        let cornerRadii: DOMCornerRadii?
        if shaped.cornerRadiusPixels > 0.5 {
            let pointRadius = Double(shaped.cornerRadiusPixels / safeScale)
            let r = DOMCornerRadius(width: pointRadius, height: pointRadius)
            cornerRadii = DOMCornerRadii(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r)
        } else {
            cornerRadii = nil
        }
        return NativeWindowShot(
            image: shaped.image,
            pixelScale: safeScale,
            appName: window.owningApplication?.applicationName ?? "Window",
            cornerRadii: cornerRadii
        )
    }

    /// Round the on-screen color crop's corners to the window's real shape.
    ///
    /// Color is the on-screen crop (only it shows vibrancy filled correctly).
    /// The crop fills the image edge-to-edge, so a mask built in its own grid
    /// aligns exactly — using the shape capture's alpha misaligns by the two
    /// APIs' sub-pixel phase and aliases. Radius is measured from the shape (a
    /// grid-independent scalar); the curve is the system's own
    /// `.continuous` corner, matching this macOS version at any radius without
    /// hardcoded constants.
    private func shapedWindowImage(_ visibleImage: CGImage,
                                   windowShape: CGImage,
                                   pixelScale: CGFloat) -> (image: CGImage, cornerRadiusPixels: CGFloat) {
        let width = visibleImage.width
        let height = visibleImage.height
        guard width > 0, height > 0 else { return (visibleImage, 0) }

        let radius = NativeWindowShaping.cornerRadius(
            shapeRadius: cornerRadiusPixels(in: windowShape),
            shapeSize: CGSize(width: windowShape.width, height: windowShape.height),
            colorSize: CGSize(width: width, height: height)
        )
        guard radius > 0.5,
              let mask = continuousCornerMask(
                width: width, height: height, radius: radius, pixelScale: pixelScale
              ) else {
            return (visibleImage, 0)
        }

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return (visibleImage, 0) }

        context.interpolationQuality = .high
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.clip(to: rect, mask: mask)
        context.draw(visibleImage, in: rect)
        return (context.makeImage() ?? visibleImage, radius)
    }

    /// White-inside / black-outside mask using the system's continuous (squircle)
    /// corner. Supersampled then downscaled because `CALayer.render(in:)` corner
    /// AA is crude and phase-varies per corner. Inset by ~1pt (scaled to pixels)
    /// to trim the window/desktop edge blend so no halo remains.
    private func continuousCornerMask(width: Int,
                                      height: Int,
                                      radius: CGFloat,
                                      pixelScale: CGFloat) -> CGImage? {
        let pixelCount = max(1, width * height)
        let maxSupersampledPixels = 32_000_000
        let affordableSampling = Int(
            sqrt(Double(maxSupersampledPixels) / Double(pixelCount))
                .rounded(.down)
        )
        let sampling = max(1, min(4, affordableSampling))
        let bigWidth = width * sampling
        let bigHeight = height * sampling
        let gray = CGColorSpaceCreateDeviceGray()
        let info = CGImageAlphaInfo.none.rawValue

        guard let bigContext = CGContext(
            data: nil, width: bigWidth, height: bigHeight,
            bitsPerComponent: 8, bytesPerRow: 0, space: gray, bitmapInfo: info
        ) else { return nil }

        let insetPoints = max(1, pixelScale.rounded())   // ~1pt of edge blend
        let inset = insetPoints * CGFloat(sampling)
        let frame = CGRect(x: 0, y: 0, width: bigWidth, height: bigHeight).insetBy(dx: inset, dy: inset)
        let containerLayer = CALayer()
        containerLayer.bounds = CGRect(x: 0, y: 0, width: bigWidth, height: bigHeight)

        let roundedLayer = CALayer()
        roundedLayer.frame = frame
        roundedLayer.backgroundColor = CGColor(gray: 1, alpha: 1)
        roundedLayer.cornerRadius = min(radius * CGFloat(sampling), min(frame.width, frame.height) / 2)
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

    /// Sub-pixel corner radius (px) from the shape alpha: scan each corner's
    /// inward diagonal (stays transparent until it hits the corner, so edge AA
    /// doesn't skew it) and take the median; crossing sits at t = r·(1−1/√2).
    private func cornerRadiusPixels(in shape: CGImage) -> CGFloat {
        let width = shape.width
        let height = shape.height
        guard width > 16, height > 16 else { return 0 }

        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &data, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return 0 }
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
                    return (CGFloat(step - 1) + fraction) / CGFloat(diagonalFactor)
                }
                previous = value
            }
            return 0
        }

        let radii = [
            radius(cornerX: 0, cornerY: 0, stepX: 1, stepY: 1),
            radius(cornerX: width - 1, cornerY: 0, stepX: -1, stepY: 1),
            radius(cornerX: width - 1, cornerY: height - 1, stepX: -1, stepY: -1),
            radius(cornerX: 0, cornerY: height - 1, stepX: 1, stepY: -1)
        ].sorted()
        return (radii[1] + radii[2]) / 2
    }

    private func captureBitmap(region: NativeCaptureRegion,
                               display: SCDisplay,
                               scale: CGFloat,
                               outputPixelSize: CGSize? = nil) async throws -> NativeCaptureBitmap {
        let filter = SCContentFilter(display: display, excludingWindows: [])

        // `pointPixelScale` is ScreenCaptureKit's own point→pixel factor for this
        // display — the authoritative Retina backing scale, correct across mixed-DPI
        // and external displays where the NSScreen value can be stale. Fall back to
        // the caller's NSScreen-derived scale on systems without the property.
        var pixelScale = scale
        if #available(macOS 14.0, *) {
            let sckScale = CGFloat(filter.pointPixelScale)
            if sckScale > 0 { pixelScale = sckScale }
        }

        let config = SCStreamConfiguration()
        config.sourceRect = region.sourceRect
        // For display capture the output pixel count is governed solely by width/
        // height (point size × pixel scale). `captureResolution = .best` is omitted
        // deliberately: per Apple's docs it only affects independent-window capture,
        // so it is a no-op on this display filter.
        config.width = max(1, Int((outputPixelSize?.width ?? region.sourceRect.width * pixelScale).rounded()))
        config.height = max(1, Int((outputPixelSize?.height ?? region.sourceRect.height * pixelScale).rounded()))
        config.scalesToFit = false
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        return NativeCaptureBitmap(image: image, pixelScale: pixelScale)
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
