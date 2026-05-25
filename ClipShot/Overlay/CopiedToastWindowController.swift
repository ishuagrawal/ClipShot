import AppKit

@MainActor
final class CopiedToastWindowController {
    private var window: NSWindow?
    private var closeWorkItem: DispatchWorkItem?

    func showCopiedToast() {
        closeWorkItem?.cancel()

        let label = NSTextField(labelWithString: "Copied")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = CGRect(x: 16, y: 10, width: 84, height: 20)

        let contentView = NSView(frame: CGRect(x: 0, y: 0, width: 116, height: 40))
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 10
        contentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        contentView.addSubview(label)

        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let frame = CGRect(
            x: screenFrame.midX - 58,
            y: screenFrame.maxY - 70,
            width: 116,
            height: 40
        )

        let toastWindow = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        toastWindow.backgroundColor = .clear
        toastWindow.isOpaque = false
        toastWindow.hasShadow = false
        toastWindow.level = .floating
        toastWindow.ignoresMouseEvents = true
        toastWindow.contentView = contentView
        toastWindow.orderFrontRegardless()

        window?.orderOut(nil)
        window = toastWindow

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.window?.orderOut(nil)
                self?.window = nil
            }
        }
        closeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }
}

