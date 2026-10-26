import AppKit
import Carbon.HIToolbox

final class HotKeyManager {
    static let shared = HotKeyManager()

    var onHotKey: (() -> Void)?
    /// Fired by ⌥⇧C: translate whatever is currently on the clipboard. Useful
    /// where a mouse selection cannot be read (terminal TUIs), so the user
    /// copies with the app's own copy command first.
    var onClipboardHotKey: (() -> Void)?

    private enum HotKeyID: UInt32 {
        case translateSelection = 1
        case translateClipboard = 2
    }

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?

    func registerDefault() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
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
            guard status == noErr else { return status }

            switch HotKeyID(rawValue: hotKeyID.id) {
            case .translateSelection:
                DebugLog.log("hotkey event received: translate selection")
                HotKeyManager.shared.onHotKey?()
            case .translateClipboard:
                DebugLog.log("hotkey event received: translate clipboard")
                HotKeyManager.shared.onClipboardHotKey?()
            case nil:
                DebugLog.log("hotkey event received: unknown id \(hotKeyID.id)")
            }
            return noErr
        }, 1, &eventType, nil, &eventHandler)
        DebugLog.log("InstallEventHandler status=\(handlerStatus)")

        let modifiers = UInt32(optionKey | shiftKey)
        register(.translateSelection, keyCode: UInt32(kVK_ANSI_T), modifiers: modifiers)
        register(.translateClipboard, keyCode: UInt32(kVK_ANSI_C), modifiers: modifiers)
    }

    private func register(_ id: HotKeyID, keyCode: UInt32, modifiers: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x54524E53), id: id.rawValue)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        DebugLog.log("RegisterEventHotKey id=\(id.rawValue) status=\(status)")
        if let ref { hotKeyRefs.append(ref) }
    }
}
