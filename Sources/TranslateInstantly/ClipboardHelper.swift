import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum ClipboardHelper {
    private static let hotKeyReleasePollInterval: TimeInterval = 0.025
    private static let copySettleDelay: TimeInterval = 0.2
    // A TUI repaint is not competing with a hotkey chord the way an AppKit text
    // field is, so the injected copy can land as soon as the modifiers are up.
    private static let terminalCopySettleDelay: TimeInterval = 0.02
    private static let pasteboardPollInterval: TimeInterval = 0.025
    private static let pasteboardPollAttempts = 200
    private static let copyAttempts = 2

    // Terminal emulators redraw their buffer constantly (TTY apps like Claude
    // Code, vim, or anything animating). During a repaint the AX tree can
    // briefly report no focused element or no AXSelectedText, so a single read
    // is unreliable and the resulting nil used to fall through to Cmd+C.
    private static let axReadAttempts = 20
    private static let axRetryInterval: TimeInterval = 0.025

    // Terminal emulators expose their line buffer as a plain AXTextArea whose
    // AXSelectedText is always empty, so the AX path cannot see a mouse
    // selection made over a full-screen TUI (Claude Code, vim, less, ...).
    // Those selections live only in the emulator's own selection state and are
    // reachable solely through its native Copy command, so terminals go
    // straight to Cmd+C instead of wasting time on AX retries.
    private static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty",
        "io.alacritty",
    ]

    // Guards against overlapping captures: if the hotkey is pressed again while
    // a previous capture is still polling, two concurrent calls would race on
    // the same pasteboard and corrupt each other's restore step.
    private static var isCapturing = false

    static func captureSelectedText(completion: @escaping (String?) -> Void) {
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let isTerminal = frontmostBundleID.map(terminalBundleIdentifiers.contains) ?? false

        // Terminals never answer the AX path for a TUI selection, so skip
        // straight to their native Copy instead of burning ~500 ms on retries.
        if isTerminal {
            DebugLog.log("terminal \(frontmostBundleID ?? "unknown"); using Copy")
            captureViaCopyKeystroke(settleDelay: terminalCopySettleDelay, completion: completion)
            return
        }

        // Everywhere else, prefer reading the selection straight from the
        // Accessibility API: no clipboard involved, no synthetic keystroke to
        // race against real hardware modifier state.
        captureViaAccessibility(attemptsRemaining: axReadAttempts, completion: completion)
    }

    private static func captureViaAccessibility(attemptsRemaining: Int, completion: @escaping (String?) -> Void) {
        if let axText = selectedTextViaAccessibility(), !axText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DebugLog.log("captured via Accessibility API")
            completion(axText)
            return
        }

        if attemptsRemaining > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + axRetryInterval) {
                captureViaAccessibility(attemptsRemaining: attemptsRemaining - 1, completion: completion)
            }
            return
        }

        captureViaCopyKeystroke(settleDelay: copySettleDelay, completion: completion)
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

        // WebKit's AXSelectedText can be shifted by a character in editable
        // web content (it drops the first letter and adds the one after the
        // selection), so let the browser's own Copy handle web pages.
        if isInsideWebArea(focusedElementRef as! AXUIElement) {
            DebugLog.log("focused element is web content; using Copy instead of AX")
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

    private static func isInsideWebArea(_ start: AXUIElement) -> Bool {
        var element = start
        for _ in 0..<32 {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
               roleRef as? String == "AXWebArea" {
                return true
            }

            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parentRef else { return false }
            element = parentRef as! AXUIElement
        }
        return false
    }

    private static func captureViaCopyKeystroke(settleDelay: TimeInterval, completion: @escaping (String?) -> Void) {
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
            DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay) {
                attemptCopy(
                    pasteboard,
                    previousItems: previousItems,
                    settleDelay: settleDelay,
                    attemptsRemaining: copyAttempts,
                    completion: completion
                )
            }
        }
    }

    private static func attemptCopy(
        _ pasteboard: NSPasteboard,
        previousItems: [[(NSPasteboard.PasteboardType, Data)]],
        settleDelay: TimeInterval,
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
            DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay) {
                attemptCopy(
                    pasteboard,
                    previousItems: previousItems,
                    settleDelay: settleDelay,
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
        // Synthetic input needs kTCCServicePostEvent (separate from the AX read
        // grant). Without it post() silently no-ops, which looks identical to
        // "the app ignored Cmd+C", so log the permission state for diagnosis.
        if #available(macOS 10.15, *) {
            DebugLog.log("postEventAccess=\(CGPreflightPostEventAccess()) axTrusted=\(AXIsProcessTrusted())")
        }

        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        // .cgAnnotatedSessionEventTap reaches the focused app through the same
        // path as real HID keystrokes; .cghidEventTap is sometimes filtered in
        // terminal emulators that already have an event tap installed.
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
