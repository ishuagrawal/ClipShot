import AppKit
import ApplicationServices

struct SelectionCandidate: Identifiable, @unchecked Sendable {
    let id = UUID()
    let role: String
    let title: String?
    let axFrame: CGRect
    let cocoaFrame: CGRect
    let isWebContent: Bool

    var displayName: String {
        let name = AccessibilityDetector.friendlyName(forRole: role)
        guard let title, !title.isEmpty else {
            return name
        }
        return "\(name): \(title)"
    }

    var signature: String {
        let frame = axFrame.integral
        return "\(role)-\(Int(frame.minX))-\(Int(frame.minY))-\(Int(frame.width))-\(Int(frame.height))"
    }

    var frameSignature: String {
        let frame = axFrame.integral
        return "\(Int(frame.minX))-\(Int(frame.minY))-\(Int(frame.width))-\(Int(frame.height))"
    }

    var area: CGFloat {
        axFrame.width * axFrame.height
    }
}

final class AccessibilityDetector {
    private static let webAreaRole = "AXWebArea"
    private static let hasDocumentRoleAncestorAttribute = "AXHasDocumentRoleAncestor"
    private static let webApplicationSubrole = "AXWebApplication"
    private static let browserBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "company.thebrowser.Browser"
    ]
    private static let browserChromeRoles: Set<String> = [
        "AXApplication",
        "AXBrowser",
        "AXDockItem",
        "AXDrawer",
        "AXHelpTag",
        "AXMenu",
        "AXMenuBar",
        "AXMenuBarItem",
        "AXMenuItem",
        "AXRuler",
        "AXRulerMarker",
        "AXScrollBar",
        "AXSheet",
        "AXSplitGroup",
        "AXSplitter",
        "AXTabGroup",
        "AXToolbar",
        "AXWindow"
    ]

    private let systemWideElement = AXUIElementCreateSystemWide()
    private let maxVisibleNodes = 3_500
    private let maxVisibleCandidates = 900
    private let maxDepth = 16

    func candidates(atAXPoint point: CGPoint) -> [SelectionCandidate] {
        var hitElement: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(point.x),
            Float(point.y),
            &hitElement
        )

        guard error == .success, let hitElement else {
            return []
        }

        var chain: [(element: AXUIElement, role: String)] = []
        var currentElement: AXUIElement? = hitElement

        for _ in 0..<14 {
            guard let element = currentElement else {
                break
            }

            let role = stringAttribute(kAXRoleAttribute, for: element) ?? "AXElement"
            chain.append((element, role))
            currentElement = parent(of: element)
        }

        if chain.contains(where: { isWebContentElement($0.element, role: $0.role) }) {
            return webCandidates(fromHitChain: chain)
        }

        guard !chain.contains(where: { Self.isBrowserChromeRole($0.role) }) else {
            return []
        }

        var seenFrames = Set<String>()
        var results: [SelectionCandidate] = []

        for item in chain {
            guard let candidate = candidate(for: item.element, role: item.role, isWebContent: false),
                  isSelectableCandidate(candidate),
                  !seenFrames.contains(candidate.signature) else {
                continue
            }

            results.append(candidate)
            seenFrames.insert(candidate.signature)
        }

        return results
    }

    func visibleCandidates(preferredProcessIdentifier: pid_t? = nil) -> [SelectionCandidate] {
        var results: [SelectionCandidate] = []
        var seenFrames = Set<String>()
        var visitedNodes = 0
        let currentPID = ProcessInfo.processInfo.processIdentifier

        let visibleApps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.processIdentifier != currentPID
                    && !app.isHidden
                    && (app.activationPolicy == .regular || app.activationPolicy == .accessory)
            }
        let apps: [NSRunningApplication]
        if let preferredProcessIdentifier,
           let preferredApp = visibleApps.first(where: { $0.processIdentifier == preferredProcessIdentifier }) {
            apps = [preferredApp]
        } else {
            apps = visibleApps
        }

        for app in apps {
            guard results.count < maxVisibleCandidates else {
                break
            }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.03)

            var appCandidates: [SelectionCandidate] = []
            var appSeenFrames = Set<String>()
            let roots = elementArrayAttribute(kAXWindowsAttribute, for: appElement)
            var queue = roots.isEmpty ? [(appElement, 0, false)] : roots.map { ($0, 0, false) }
            var queueIndex = 0

            while queueIndex < queue.count,
                  appCandidates.count < maxVisibleCandidates,
                  visitedNodes < maxVisibleNodes {
                let (element, depth, parentIsWebContent) = queue[queueIndex]
                queueIndex += 1
                visitedNodes += 1

                let role = stringAttribute(kAXRoleAttribute, for: element) ?? "AXElement"
                let isWebContent = parentIsWebContent || isWebContentElement(element, role: role)

                if let candidate = candidate(for: element, role: role, isWebContent: isWebContent),
                   isSelectableCandidate(candidate),
                   !appSeenFrames.contains(candidate.frameSignature) {
                    appCandidates.append(candidate)
                    appSeenFrames.insert(candidate.frameSignature)
                }

                guard depth < maxDepth else {
                    continue
                }

                let children = elementArrayAttribute(kAXChildrenAttribute, for: element)
                queue.append(contentsOf: children.map { ($0, depth + 1, isWebContent) })
            }

            let webCandidates = appCandidates.filter(\.isWebContent)
            let selectedCandidates: [SelectionCandidate]
            if !webCandidates.isEmpty {
                selectedCandidates = webCandidates
            } else if Self.isKnownBrowser(app) {
                selectedCandidates = []
            } else {
                selectedCandidates = appCandidates
            }

            for candidate in selectedCandidates {
                guard results.count < maxVisibleCandidates,
                      !seenFrames.contains(candidate.frameSignature) else {
                    continue
                }
                results.append(candidate)
                seenFrames.insert(candidate.frameSignature)
            }
        }

        return results.sorted { left, right in
            if left.area == right.area {
                return left.role < right.role
            }
            return left.area < right.area
        }
    }

    static func friendlyName(forRole role: String) -> String {
        switch role {
        case kAXButtonRole:
            return "Button"
        case kAXStaticTextRole:
            return "Text"
        case kAXTextFieldRole:
            return "Text field"
        case kAXImageRole:
            return "Image"
        case kAXGroupRole:
            return "Group"
        case kAXHeadingRole:
            return "Heading"
        case kAXScrollAreaRole:
            return "Scroll area"
        case kAXWindowRole:
            return "Window"
        case kAXSheetRole:
            return "Sheet"
        case kAXToolbarRole:
            return "Toolbar"
        case Self.webAreaRole:
            return "Web page"
        case "AXLink":
            return "Link"
        case "AXLandmark":
            return "Landmark"
        default:
            return role.replacingOccurrences(of: "AX", with: "")
        }
    }

    private func webCandidates(fromHitChain chain: [(element: AXUIElement, role: String)]) -> [SelectionCandidate] {
        var results: [SelectionCandidate] = []
        var seenFrames = Set<String>()
        let webAreaIndex = chain.firstIndex { $0.role == Self.webAreaRole }
        let chromeIndex = chain.firstIndex { Self.isBrowserChromeRole($0.role) }
        let upperBound = webAreaIndex ?? chromeIndex ?? chain.count
        let candidatesRange = chain.indices.filter { $0 < upperBound }

        for index in candidatesRange {
            let item = chain[index]
            guard let candidate = candidate(for: item.element, role: item.role, isWebContent: true),
                  isSelectableCandidate(candidate),
                  !seenFrames.contains(candidate.signature) else {
                continue
            }

            results.append(candidate)
            seenFrames.insert(candidate.signature)
        }

        if results.isEmpty,
           let webAreaIndex,
           let webAreaCandidate = candidate(
            for: chain[webAreaIndex].element,
            role: chain[webAreaIndex].role,
            isWebContent: true
           ) {
            results.append(webAreaCandidate)
        }

        return results
    }

    private func bestTitle(for element: AXUIElement) -> String? {
        stringAttribute(kAXTitleAttribute, for: element)
            ?? stringAttribute(kAXDescriptionAttribute, for: element)
            ?? stringAttribute(kAXValueAttribute, for: element)
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success else {
            return nil
        }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func candidate(for element: AXUIElement, role: String? = nil, isWebContent: Bool = false) -> SelectionCandidate? {
        guard let frame = frame(for: element), isUseful(frame: frame) else {
            return nil
        }

        let role = role ?? stringAttribute(kAXRoleAttribute, for: element) ?? "AXElement"
        return SelectionCandidate(
            role: role,
            title: bestTitle(for: element),
            axFrame: frame.integral,
            cocoaFrame: CoordinateSpace.cocoaRect(fromAXRect: frame).integral,
            isWebContent: isWebContent
        )
    }

    private func isSelectableCandidate(_ candidate: SelectionCandidate) -> Bool {
        if Self.isBrowserChromeRole(candidate.role) {
            return false
        }

        if candidate.isWebContent {
            return candidate.role != Self.webAreaRole
        }

        return true
    }

    private func isWebContentElement(_ element: AXUIElement, role: String) -> Bool {
        if role == Self.webAreaRole {
            return true
        }

        if boolAttribute(Self.hasDocumentRoleAncestorAttribute, for: element) == true {
            return true
        }

        return stringAttribute(kAXSubroleAttribute, for: element) == Self.webApplicationSubrole
    }

    private static func isBrowserChromeRole(_ role: String) -> Bool {
        browserChromeRoles.contains(role)
    }

    private static func isKnownBrowser(_ app: NSRunningApplication) -> Bool {
        guard let bundleIdentifier = app.bundleIdentifier else {
            return false
        }
        return browserBundleIdentifiers.contains(bundleIdentifier)
    }

    private func frame(for element: AXUIElement) -> CGRect? {
        guard let position = cgPointAttribute(kAXPositionAttribute, for: element),
              let size = cgSizeAttribute(kAXSizeAttribute, for: element) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func stringAttribute(_ attribute: String, for element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func boolAttribute(_ attribute: String, for element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? Bool
    }

    private func elementArrayAttribute(_ attribute: String, for element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == CFArrayGetTypeID() else {
            return []
        }

        let array = value as! NSArray
        return array.compactMap { item in
            let value = item as CFTypeRef
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
                return nil
            }
            return (value as! AXUIElement)
        }
    }

    private func cgPointAttribute(_ attribute: String, for element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard
              AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func cgSizeAttribute(_ attribute: String, for element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard
              AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func isUseful(frame: CGRect) -> Bool {
        guard frame.width >= 12, frame.height >= 12 else {
            return false
        }

        let desktop = CoordinateSpace.axDesktopBounds
        guard desktop.intersects(frame) else {
            return false
        }

        return frame.width <= desktop.width + 2 && frame.height <= desktop.height + 2
    }
}
