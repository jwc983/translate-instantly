import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum ClipboardHelper {
    private static let hotKeyReleasePollInterval: TimeInterval = 0.025
    private static let copySettleDelay: TimeInterval = 0.075
    private static let pasteboardPollInterval: TimeInterval = 0.025
    private static let pasteboardPollAttempts = 60
    private static let copyAttempts = 2

    // Guards against overlapping captures: if the hotkey is pressed again while
    // a previous capture is still polling, two concurrent calls would race on
    // the same pasteboard and corrupt each other's restore step.
    private static var isCapturing = false

    static func captureSelectedText(completion: @escaping (String?) -> Void) {
        // Prefer reading the selection straight from the Accessibility API: no
        // clipboard involved, no synthetic keystroke to race against real
        // hardware modifier state. Terminal.app in particular treats the
        // synthetic Cmd+C from the fallback path below as unreliable (its
        // AXSelectedText support is solid, but CGEvent-injected keystrokes
        // often lose the race against the still-being-released hotkey chord).
        if let axText = selectedTextViaAccessibility(), !axText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DebugLog.log("captured via Accessibility API")
            completion(axText)
            return
        }

        captureViaCopyKeystroke(completion: completion)
    }

    private static func selectedTextViaAccessibility() -> String? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(frontmost.processIdentifier)

        var focusedElementRef: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElementRef)
        guard focusedResult == .success,
              let focusedElementRef = focusedElementRef else {
            DebugLog.log("AX focused element lookup failed: \(focusedResult.rawValue)")
            return nil
        }

        // Some applications expose AXSelectedText on a container rather than
        // the leaf that macOS reports as focused. Walk toward the application
        // before falling back to a synthetic Copy command.
        var element = focusedElementRef as! AXUIElement
        for _ in 0..<8 {
            var selectedTextRef: CFTypeRef?
            let selectedResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextRef)
            if selectedResult == .success, let text = selectedTextRef as? String {
                return text
            }

            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parentRef else { break }
            element = parentRef as! AXUIElement
        }

        DebugLog.log("AX selected text unavailable for \(frontmost.bundleIdentifier ?? "unknown")")
        return nil
    }

    private static func captureViaCopyKeystroke(completion: @escaping (String?) -> Void) {
        guard !isCapturing else {
            DebugLog.log("captureSelectedText ignored: capture already in progress")
            completion(nil)
            return
        }
        isCapturing = true

        let frontmostApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        let secureInput = IsSecureEventInputEnabled()
        DebugLog.log("captureViaCopyKeystroke starting, frontmostApp=\(frontmostApp) secureEventInput=\(secureInput)")

        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        } ?? []

        waitForHotKeyRelease(attemptsRemaining: 40) {
            // Carbon reports the hotkey on key-down. Give the source app a
            // moment to process every matching key-up before injecting Cmd+C.
            DispatchQueue.main.asyncAfter(deadline: .now() + copySettleDelay) {
                attemptCopy(
                    pasteboard,
                    previousItems: previousItems,
                    attemptsRemaining: copyAttempts,
                    completion: completion
                )
            }
        }
    }

    private static func attemptCopy(
        _ pasteboard: NSPasteboard,
        previousItems: [[(NSPasteboard.PasteboardType, Data)]],
        attemptsRemaining: Int,
        completion: @escaping (String?) -> Void
    ) {
        let changeCountBeforeCopy = pasteboard.changeCount
        simulateCopyKeystroke()

        pollForPasteboardChange(
            pasteboard,
            previousChangeCount: changeCountBeforeCopy,
            attemptsRemaining: pasteboardPollAttempts
        ) { changed in
            let text = changed ? pasteboard.string(forType: .string) : nil
            let hasText = text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

            if hasText {
                restore(previousItems, to: pasteboard)
                finishCapture(with: text, completion: completion)
                return
            }

            if changed {
                // Keep retries isolated from clipboard content produced by a
                // failed/non-text copy, and ultimately preserve the user's
                // original clipboard just as the successful path does.
                restore(previousItems, to: pasteboard)
            }

            guard attemptsRemaining > 1 else {
                let reason = changed ? "pasteboard changed without plain text" : "pasteboard did not change"
                DebugLog.log("captureSelectedText failed: \(reason) after \(copyAttempts) copy attempts")
                finishCapture(with: nil, completion: completion)
                return
            }

            DebugLog.log("copy attempt failed; retrying")
            DispatchQueue.main.asyncAfter(deadline: .now() + copySettleDelay) {
                attemptCopy(
                    pasteboard,
                    previousItems: previousItems,
                    attemptsRemaining: attemptsRemaining - 1,
                    completion: completion
                )
            }
        }
    }

    private static func finishCapture(with text: String?, completion: @escaping (String?) -> Void) {
        isCapturing = false
        completion(text)
    }

    private static func waitForHotKeyRelease(attemptsRemaining: Int, completion: @escaping () -> Void) {
        let hotKeyKeys = [kVK_Option, kVK_RightOption, kVK_Shift, kVK_RightShift, kVK_ANSI_T]
        let hotKeyStillDown = hotKeyKeys.contains {
            CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0))
        }
        guard hotKeyStillDown else {
            completion()
            return
        }
        guard attemptsRemaining > 0 else {
            DebugLog.log("hotkey keys still down; attempting copy after timeout")
            completion()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + hotKeyReleasePollInterval) {
            waitForHotKeyRelease(attemptsRemaining: attemptsRemaining - 1, completion: completion)
        }
    }

    private static func restore(_ items: [[(NSPasteboard.PasteboardType, Data)]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { representations -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in representations {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }

    private static func pollForPasteboardChange(
        _ pasteboard: NSPasteboard,
        previousChangeCount: Int,
        attemptsRemaining: Int,
        completion: @escaping (Bool) -> Void
    ) {
        if pasteboard.changeCount != previousChangeCount {
            completion(true)
            return
        }
        guard attemptsRemaining > 0 else {
            completion(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteboardPollInterval) {
            pollForPasteboardChange(pasteboard, previousChangeCount: previousChangeCount, attemptsRemaining: attemptsRemaining - 1, completion: completion)
        }
    }

    private static func simulateCopyKeystroke() {
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
