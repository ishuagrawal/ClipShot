import Carbon.HIToolbox
import Foundation

@MainActor
final class NativeCaptureShortcut {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    @discardableResult
    func register() -> Bool {
        let eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                var hotKeyID = EventHotKeyID()
                let idSize = MemoryLayout<EventHotKeyID>.size
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    idSize,
                    nil,
                    &hotKeyID
                )

                guard hotKeyID.signature == NativeCaptureShortcut.signature,
                      hotKeyID.id == NativeCaptureShortcut.hotKeyID else {
                    return noErr
                }

                let shortcut = Unmanaged<NativeCaptureShortcut>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    shortcut.handler()
                }
                return noErr
            },
            1,
            [eventSpec],
            unmanagedSelf,
            &eventHandlerRef
        )
        guard status == noErr else { return false }

        let id = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_5),
            UInt32(controlKey | shiftKey),
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard hotKeyStatus == noErr else {
            unregister()
            return false
        }
        return true
    }

    private static let hotKeyID = UInt32(5)
    private static let signature = OSType(
        UInt32(Character("C").asciiValue!) << 24
            | UInt32(Character("S").asciiValue!) << 16
            | UInt32(Character("H").asciiValue!) << 8
            | UInt32(Character("T").asciiValue!)
    )
}
