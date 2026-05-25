import AppKit

enum CoordinateSpace {
    static var cocoaDesktopBounds: CGRect {
        NSScreen.screens.reduce(CGRect.null) { partialResult, screen in
            partialResult.union(screen.frame)
        }
    }

    static var axDesktopBounds: CGRect {
        activeDisplayIDs.reduce(CGRect.null) { partialResult, displayID in
            partialResult.union(CGDisplayBounds(displayID))
        }
    }

    static func axPoint(fromCocoaPoint point: CGPoint) -> CGPoint {
        guard let screen = screen(containingCocoaPoint: point),
              let displayID = displayID(for: screen) else {
            return point
        }

        let screenFrame = screen.frame
        let displayBounds = CGDisplayBounds(displayID)
        let localX = point.x - screenFrame.minX
        let localYFromBottom = point.y - screenFrame.minY

        return CGPoint(
            x: displayBounds.minX + localX,
            y: displayBounds.maxY - localYFromBottom
        )
    }

    static func cocoaRect(fromAXRect rect: CGRect) -> CGRect {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let displayID = displayID(containingAXPoint: center),
              let screen = screen(forDisplayID: displayID) else {
            return rect
        }

        let displayBounds = CGDisplayBounds(displayID)
        let screenFrame = screen.frame
        let localX = rect.minX - displayBounds.minX
        let localYFromTop = rect.minY - displayBounds.minY

        return CGRect(
            x: screenFrame.minX + localX,
            y: screenFrame.maxY - localYFromTop - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private static var activeDisplayIDs: [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }

        var displays = Array(repeating: CGDirectDisplayID(0), count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return []
        }

        return Array(displays.prefix(Int(count)))
    }

    private static func screen(containingCocoaPoint point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    private static func screen(forDisplayID displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            self.displayID(for: screen) == displayID
        }
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    private static func displayID(containingAXPoint point: CGPoint) -> CGDirectDisplayID? {
        var displayID = CGDirectDisplayID(0)
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &displayID, &count) == .success, count > 0 else {
            return nil
        }
        return displayID
    }
}
