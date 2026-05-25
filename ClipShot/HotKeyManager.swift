import AppKit
import Carbon
import Foundation

final class HotKeyManager: @unchecked Sendable {
    private static let signature: OSType = 0x434C4950

    private let onHotKey: @Sendable () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(onHotKey: @escaping @Sendable () -> Void) {
        self.onHotKey = onHotKey
    }

    @discardableResult
    func register() -> Bool {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr,
                      hotKeyID.signature == HotKeyManager.signature,
                      hotKeyID.id == 1 else {
                    return noErr
                }

                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onHotKey()
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_5),
            UInt32(cmdKey | optionKey | controlKey),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.matchesShortcut(event) else {
                return
            }
            self?.onHotKey()
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.matchesShortcut(event) else {
                return event
            }
            self?.onHotKey()
            return nil
        }

        return (handlerStatus == noErr && hotKeyStatus == noErr) || globalMonitor != nil || localMonitor != nil
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

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private static func matchesShortcut(_ event: NSEvent) -> Bool {
        guard event.keyCode == UInt16(kVK_ANSI_5) else {
            return false
        }

        let requiredFlags: NSEvent.ModifierFlags = [.command, .option, .control]
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.isSuperset(of: requiredFlags)
    }
}
