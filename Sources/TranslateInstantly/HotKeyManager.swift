import AppKit
import Carbon.HIToolbox

final class HotKeyManager {
    static let shared = HotKeyManager()

    var onHotKey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func registerDefault() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DebugLog.log("hotkey event received")
            HotKeyManager.shared.onHotKey?()
            return noErr
        }, 1, &eventType, nil, &eventHandler)
        DebugLog.log("InstallEventHandler status=\(handlerStatus)")

        let hotKeyID = EventHotKeyID(signature: OSType(0x54524E53), id: 1)
        let modifiers = UInt32(optionKey | shiftKey)
        let registerStatus = RegisterEventHotKey(UInt32(kVK_ANSI_T), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        DebugLog.log("RegisterEventHotKey status=\(registerStatus)")
    }
}
