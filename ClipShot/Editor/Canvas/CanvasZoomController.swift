import CoreGraphics
import SwiftUI

/// Pure zoom arithmetic. Lives apart from AppKit so it is unit-testable without a
/// laid-out scroll view. `CanvasScrollView` sources its magnification limits here too,
/// so there is a single source of truth for the bounds.
enum ZoomMath {
    static let minMagnification: CGFloat = 0.05   // 5%
    static let maxMagnification: CGFloat = 16      // 1600%

    /// Discrete levels offered by the percentage dropdown.
    static let presets: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.5, 2, 4]

    /// "Nice" zoom stops the +/- buttons snap to (ascending). Stepping moves to the
    /// next stop in the press direction, so an off-grid level (from pinch or a fit)
    /// lands on a clean number.
    static let zoomStops: [CGFloat] = [
        0.05, 0.10, 0.15, 0.25, 0.33, 0.5, 0.67, 0.75,
        1, 1.25, 1.5, 2, 3, 4, 6, 8, 12, 16
    ]

    static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, minMagnification), maxMagnification)
    }

    /// Next "nice" magnification when stepping. `direction > 0` zooms in, `< 0` out.
    /// Snaps to the nearest stop strictly past `current` in that direction.
    static func stepped(_ current: CGFloat, direction: Int) -> CGFloat {
        guard direction != 0 else { return clamp(current) }
        let c = clamp(current)
        if direction > 0 {
            return zoomStops.first(where: { $0 > c + 0.0001 }) ?? maxMagnification
        } else {
            return zoomStops.last(where: { $0 < c - 0.0001 }) ?? minMagnification
        }
    }

    static func percentLabel(_ magnification: CGFloat) -> String {
        "\(Int((magnification * 100).rounded()))%"
    }
}

/// SwiftUI-facing bridge to the AppKit zoom state. Publishes the live magnification
/// (so the percentage readout tracks pinch / cmd-scroll / programmatic changes) and
/// forwards control actions to the `CanvasCoordinator`.
@MainActor
final class CanvasZoomController: ObservableObject {
    @Published private(set) var magnification: CGFloat = 1

    private weak var coordinator: CanvasCoordinator?

    var presets: [CGFloat] { ZoomMath.presets }
    var percentLabel: String { ZoomMath.percentLabel(magnification) }
    var canZoomIn: Bool { magnification < ZoomMath.maxMagnification - 0.0001 }
    var canZoomOut: Bool { magnification > ZoomMath.minMagnification + 0.0001 }

    func attach(_ coordinator: CanvasCoordinator) {
        // CanvasView.updateNSView calls this on every SwiftUI update. Wire the callback
        // only once (coordinator identity is stable), and never publish synchronously
        // here — publishing within a view update is undefined behavior, and an
        // unconditional set would re-invalidate the view and loop forever.
        if self.coordinator !== coordinator {
            self.coordinator = coordinator
            coordinator.onMagnificationChange = { [weak self] mag in
                self?.publishMagnification(mag)
            }
        }
        publishMagnification(coordinator.currentMagnification)
    }

    /// Publish only on real change (breaks the invalidation loop) and off the current
    /// run loop turn (so it never fires inside a SwiftUI view update).
    private func publishMagnification(_ mag: CGFloat) {
        guard abs(mag - magnification) > 0.0001 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, abs(mag - self.magnification) > 0.0001 else { return }
            self.magnification = mag
        }
    }

    func zoomIn()  { coordinator?.controlZoom(to: ZoomMath.stepped(magnification, direction: 1)) }
    func zoomOut() { coordinator?.controlZoom(to: ZoomMath.stepped(magnification, direction: -1)) }
    func setZoom(_ value: CGFloat) { coordinator?.controlZoom(to: value) }

    /// Scale so the whole image fills the viewport edge-to-edge.
    func fitToCanvas() { coordinator?.fitImageToCanvas() }

    /// Scale so the selected screenshot region fills the viewport.
    func fitToSelection() { coordinator?.fitSelectionToCanvas() }

    /// Restore the framing the canvas shows on first load (selection centered with margin).
    func resetToCenter() { coordinator?.resetToInitialFit() }
}
