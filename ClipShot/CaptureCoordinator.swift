import AppKit

@MainActor
final class CaptureCoordinator {
    private let appState: AppState
    private let detector = AccessibilityDetector()
    private let captureService = ScreenCaptureService()
    private let toastController = CopiedToastWindowController()

    private var overlayControllers: [OverlayWindowController] = []
    private var visibleCandidateScanTask: Task<Void, Never>?
    private var visibleCandidates: [SelectionCandidate] = []
    private var candidates: [SelectionCandidate] = []
    private var selectedIndex = 0
    private var lastCandidateSignature: [String] = []
    private var isCapturing = false
    private var captureGeneration = 0

    init(appState: AppState) {
        self.appState = appState
    }

    func startCapture() {
        appState.refreshPermissions()

        if !appState.hasScreenRecordingPermission {
            PermissionManager.requestScreenRecordingPermission()
        }

        if !appState.hasAccessibilityPermission {
            PermissionManager.requestAccessibilityPermission()
        }

        guard !isCapturing else {
            return
        }

        let preferredProcessIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier
        captureGeneration += 1
        let generation = captureGeneration
        isCapturing = true
        appState.setCaptureStatus("Capture mode")
        visibleCandidates = []
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)

        overlayControllers = NSScreen.screens.map { screen in
            let controller = OverlayWindowController(screen: screen)
            controller.onMouseMoved = { [weak self] point in
                self?.updateSelection(atCocoaPoint: point)
            }
            controller.onConfirm = { [weak self] in
                self?.captureCurrentSelection()
            }
            controller.onCancel = { [weak self] in
                self?.cancelCapture()
            }
            controller.onCycle = { [weak self] in
                self?.cycleSelection()
            }
            return controller
        }

        overlayControllers.forEach { $0.show() }
        updateSelection(atCocoaPoint: NSEvent.mouseLocation)
        startVisibleCandidateScan(
            preferredProcessIdentifier: preferredProcessIdentifier,
            generation: generation
        )
    }

    func cancelCapture() {
        tearDownOverlay()
        appState.setCaptureStatus("Cancelled")
    }

    func copyDOMPNGToClipboard(pngData: Data) -> Bool {
        let didCopy = captureService.copyPNGDataToClipboard(pngData)
        reportCopyResult(didCopy)
        return didCopy
    }

    func copyDOMScreenFrameToClipboard(screenFrame: CGRect) -> Bool {
        let didCopy = captureService.copyPNGToClipboard(screenFrame: screenFrame)
        reportCopyResult(didCopy)
        return didCopy
    }

    private func cycleSelection() {
        guard !candidates.isEmpty else {
            NSSound.beep()
            return
        }

        selectedIndex = (selectedIndex + 1) % candidates.count
        updateOverlayViews()
    }

    private func captureCurrentSelection() {
        guard candidates.indices.contains(selectedIndex) else {
            NSSound.beep()
            return
        }

        let captureFrame = candidates[selectedIndex].axFrame
        tearDownOverlay()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            Task { @MainActor in
                self?.copyCaptureToClipboard(axFrame: captureFrame)
            }
        }
    }

    private func copyCaptureToClipboard(axFrame: CGRect) {
        reportCopyResult(captureService.copyPNGToClipboard(axFrame: axFrame))
    }

    private func reportCopyResult(_ didCopy: Bool) {
        if didCopy {
            appState.setCaptureStatus("Copied")
            toastController.showCopiedToast()
        } else {
            appState.setCaptureStatus("Capture failed")
            NSSound.beep()
        }
    }

    private func updateSelection(atCocoaPoint point: CGPoint) {
        guard isCapturing else {
            return
        }

        let axPoint = CoordinateSpace.axPoint(fromCocoaPoint: point)
        let hitCandidates = detector.candidates(atAXPoint: axPoint)
        let visibleUnderCursor = visibleCandidates
            .filter { $0.axFrame.contains(axPoint) }
            .sorted { left, right in
                if left.area == right.area {
                    return left.role < right.role
                }
                return left.area < right.area
            }
        let newCandidates = combinedCandidates(primary: hitCandidates, secondary: visibleUnderCursor)
        let newSignature = newCandidates.map(\.signature)

        if newSignature != lastCandidateSignature {
            candidates = newCandidates
            lastCandidateSignature = newSignature
            selectedIndex = 0
        }

        updateOverlayViews()
    }

    private func updateOverlayViews() {
        let selectedCandidate = candidates.indices.contains(selectedIndex) ? candidates[selectedIndex] : nil

        overlayControllers.forEach {
            $0.updateSelection(
                globalCocoaRect: selectedCandidate?.cocoaFrame,
                allGlobalCocoaRects: visibleCandidates.map(\.cocoaFrame),
                label: selectedCandidate?.displayName,
                index: selectedCandidate == nil ? nil : selectedIndex + 1,
                count: candidates.isEmpty ? nil : candidates.count
            )
        }
    }

    private func startVisibleCandidateScan(preferredProcessIdentifier: pid_t?, generation: Int) {
        visibleCandidateScanTask?.cancel()
        visibleCandidateScanTask = Task { [weak self] in
            let candidates = await Task.detached(priority: .userInitiated) {
                AccessibilityDetector().visibleCandidates(
                    preferredProcessIdentifier: preferredProcessIdentifier
                )
            }.value

            guard let self,
                  !Task.isCancelled,
                  self.isCapturing,
                  self.captureGeneration == generation else {
                return
            }

            self.visibleCandidates = candidates
            self.appState.setCaptureStatus("Capture mode - \(candidates.count) boxes")
            self.updateSelection(atCocoaPoint: NSEvent.mouseLocation)
        }
    }

    private func combinedCandidates(
        primary: [SelectionCandidate],
        secondary: [SelectionCandidate]
    ) -> [SelectionCandidate] {
        var results: [SelectionCandidate] = []
        var seenFrames = Set<String>()

        for candidate in primary + secondary {
            guard !seenFrames.contains(candidate.frameSignature) else {
                continue
            }
            results.append(candidate)
            seenFrames.insert(candidate.frameSignature)
        }

        return results
    }

    private func tearDownOverlay() {
        captureGeneration += 1
        visibleCandidateScanTask?.cancel()
        visibleCandidateScanTask = nil
        isCapturing = false
        overlayControllers.forEach { $0.closeOverlay() }
        overlayControllers = []
        visibleCandidates = []
        candidates = []
        selectedIndex = 0
        lastCandidateSignature = []
    }
}
