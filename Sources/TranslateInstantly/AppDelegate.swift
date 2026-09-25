import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        DebugLog.log("applicationWillFinishLaunching")
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(event:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.log("applicationDidFinishLaunching")
        requestAccessibilityPermissionIfNeeded()
        setupStatusItem()
        setupHotKey()
    }

    @objc private func handleGetURL(event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        DebugLog.log("handleGetURL called")
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString), url.scheme == "translateinstantly" else { return }
        translateSelection()
    }

    private func requestAccessibilityPermissionIfNeeded() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
        let options: [String: Any] = [promptKey: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "TranslateInstantly") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "译"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Set DeepSeek API Key…", action: #selector(setDeepSeekAPIKey), keyEquivalent: "")
        menu.addItem(.separator())
        let hotkeyItem = NSMenuItem(title: "Hotkey: ⌥⇧T", action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items { menuItem.target = self }
        item.menu = menu

        statusItem = item
    }

    private func setupHotKey() {
        HotKeyManager.shared.onHotKey = { [weak self] in
            self?.translateSelection()
        }
        HotKeyManager.shared.registerDefault()
    }

    private func translateSelection() {
        DebugLog.log("translateSelection triggered, AXIsProcessTrusted=\(AXIsProcessTrusted())")
        guard let apiKey = APIKeyStore.load(), !apiKey.isEmpty else {
            DebugLog.log("no DeepSeek API key set")
            let alert = NSAlert()
            alert.messageText = "DeepSeek API Key Required"
            alert.informativeText = "Set your DeepSeek API key from the menu bar icon first."
            alert.runModal()
            return
        }

        ClipboardHelper.captureSelectedText { text in
            DebugLog.log("captured text = \(text ?? "nil")")
            guard let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                TranslationPanel.shared.show(loadingFor: "")
                TranslationPanel.shared.showError("No text captured. Make sure text is selected, then try again.")
                return
            }

            TranslationPanel.shared.show(loadingFor: text)

            let handleResult: (Result<TranslationResult, Error>) -> Void = { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let translation):
                        TranslationPanel.shared.update(with: translation)
                    case .failure(let error):
                        TranslationPanel.shared.showError(error.localizedDescription)
                    }
                }
            }

            DeepSeekClient.translate(text, apiKey: apiKey, completion: handleResult)
        }
    }

    @objc private func setDeepSeekAPIKey() {
        // Presenting a modal alert synchronously inside a status-item menu action
        // leaves it unable to receive keyboard/paste input until the menu's own
        // tracking session has fully ended, so defer to the next run loop turn.
        DispatchQueue.main.async { [weak self] in
            self?.presentAPIKeyAlert()
        }
    }

    private func presentAPIKeyAlert() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "DeepSeek API Key"
        alert.informativeText = "Enter your DeepSeek API key."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = APIKeyStore.load() ?? ""
        field.placeholderString = "sk-…"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        alert.window.makeKeyAndOrderFront(nil)
        alert.window.makeFirstResponder(field)

        if alert.runModal() == .alertFirstButtonReturn {
            APIKeyStore.save(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), )
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
