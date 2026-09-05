import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var geminiProviderItem: NSMenuItem?
    private var deepseekProviderItem: NSMenuItem?

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
        menu.addItem(withTitle: "Set Gemini API Key…", action: #selector(setGeminiAPIKey), keyEquivalent: "")
        menu.addItem(withTitle: "Set DeepSeek API Key…", action: #selector(setDeepSeekAPIKey), keyEquivalent: "")
        menu.addItem(.separator())
        let geminiItem = menu.addItem(withTitle: "Use Gemini", action: #selector(selectGemini), keyEquivalent: "")
        let deepseekItem = menu.addItem(withTitle: "Use DeepSeek", action: #selector(selectDeepSeek), keyEquivalent: "")
        geminiProviderItem = geminiItem
        deepseekProviderItem = deepseekItem
        menu.addItem(.separator())
        let hotkeyItem = NSMenuItem(title: "Hotkey: ⌥⇧T", action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items { menuItem.target = self }
        item.menu = menu

        statusItem = item
        updateProviderMenuState()
    }

    private func updateProviderMenuState() {
        let active = TranslationProvider.active
        geminiProviderItem?.state = active == .gemini ? .on : .off
        deepseekProviderItem?.state = active == .deepseek ? .on : .off
    }

    @objc private func selectGemini() {
        TranslationProvider.active = .gemini
        updateProviderMenuState()
    }

    @objc private func selectDeepSeek() {
        TranslationProvider.active = .deepseek
        updateProviderMenuState()
    }

    private func setupHotKey() {
        HotKeyManager.shared.onHotKey = { [weak self] in
            self?.translateSelection()
        }
        HotKeyManager.shared.registerDefault()
    }

    private func translateSelection() {
        DebugLog.log("translateSelection triggered, AXIsProcessTrusted=\(AXIsProcessTrusted())")
        let provider = TranslationProvider.active
        guard let apiKey = APIKeyStore.load(for: provider), !apiKey.isEmpty else {
            DebugLog.log("no API key set for \(provider.rawValue)")
            let alert = NSAlert()
            alert.messageText = "\(provider.displayName) API Key Required"
            alert.informativeText = "Set your \(provider.displayName) API key from the menu bar icon first."
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

            switch provider {
            case .gemini:
                GeminiClient.translate(text, apiKey: apiKey, completion: handleResult)
            case .deepseek:
                DeepSeekClient.translate(text, apiKey: apiKey, completion: handleResult)
            }
        }
    }

    @objc private func setGeminiAPIKey() {
        // Presenting a modal alert synchronously inside a status-item menu action
        // leaves it unable to receive keyboard/paste input until the menu's own
        // tracking session has fully ended, so defer to the next run loop turn.
        DispatchQueue.main.async { [weak self] in
            self?.presentAPIKeyAlert(for: .gemini, placeholder: "AIza…")
        }
    }

    @objc private func setDeepSeekAPIKey() {
        DispatchQueue.main.async { [weak self] in
            self?.presentAPIKeyAlert(for: .deepseek, placeholder: "sk-…")
        }
    }

    private func presentAPIKeyAlert(for provider: TranslationProvider, placeholder: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "\(provider.displayName) API Key"
        alert.informativeText = "Enter your \(provider.displayName) API key."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = APIKeyStore.load(for: provider) ?? ""
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        alert.window.makeKeyAndOrderFront(nil)
        alert.window.makeFirstResponder(field)

        if alert.runModal() == .alertFirstButtonReturn {
            APIKeyStore.save(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), for: provider)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
