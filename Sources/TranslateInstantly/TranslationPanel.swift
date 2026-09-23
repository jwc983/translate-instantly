import AppKit

final class TranslationPanel: NSObject, NSTextViewDelegate, NSWindowDelegate {
    static let shared = TranslationPanel()

    private static let speakLinkScheme = "translateinstantly-speak"

    private var panel: NSPanel?
    private var textView: NSTextView?
    private var result: TranslationResult?
    private var originalText = ""
    /// What's currently on screen: the user's selection followed by the
    /// translation sections. Play links refer to indices in this array.
    private var displayedSections: [TranslationResult.Section] = []

    private override init() {
        super.init()
        SpeechPlayer.shared.onStateChange = { [weak self] in
            guard let self = self, let result = self.result else { return }
            self.update(with: result)
        }
    }

    func show(loadingFor originalText: String = "") {
        closeExisting()
        self.originalText = originalText.trimmingCharacters(in: .whitespacesAndNewlines)

        let width: CGFloat = 380
        let height: CGFloat = 240
        let mouseLocation = NSEvent.mouseLocation
        let screenFrame = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        var origin = NSPoint(x: mouseLocation.x, y: mouseLocation.y - height - 12)
        origin.x = min(max(origin.x, screenFrame.minX), screenFrame.maxX - width)
        origin.y = min(max(origin.y, screenFrame.minY), screenFrame.maxY - height)

        let frame = NSRect(x: origin.x, y: origin.y, width: width, height: height)
        let panel = NSPanel(contentRect: frame, styleMask: [.nonactivatingPanel, .titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Translation"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = panel.contentView!.bounds
        scrollView.autoresizingMask = [.width, .height]
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.string = "Translating…"
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.delegate = self
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.controlAccentColor,
            .cursor: NSCursor.pointingHand
        ]

        panel.contentView?.addSubview(scrollView)
        panel.orderFrontRegardless()

        self.panel = panel
        self.textView = textView
    }

    func update(with result: TranslationResult) {
        guard let textView = textView else { return }
        self.result = result
        displayedSections = [selectedTextSection()].compactMap { $0 } + result.sections

        let headerFont = NSFont.boldSystemFont(ofSize: 12)
        let headerColor = NSColor.secondaryLabelColor
        let bodyFont = NSFont.systemFont(ofSize: 15)

        let output = NSMutableAttributedString()
        for (index, section) in displayedSections.enumerated() where !section.body.isEmpty {
            if output.length > 0 {
                output.append(NSAttributedString(string: "\n\n"))
            }
            output.append(NSAttributedString(string: section.title, attributes: [.font: headerFont, .foregroundColor: headerColor]))
            if section.speechLanguage != nil, let link = URL(string: "\(Self.speakLinkScheme):\(index)") {
                let label = SpeechPlayer.shared.speakingID == index ? "■ Stop" : "▶ Play"
                output.append(NSAttributedString(string: "   "))
                output.append(NSAttributedString(string: label, attributes: [.font: headerFont, .link: link]))
            }
            output.append(NSAttributedString(string: "\n"))
            output.append(NSAttributedString(string: section.body, attributes: [.font: bodyFont]))
        }

        if output.length == 0 {
            output.append(NSAttributedString(string: "No translation returned.", attributes: [.font: bodyFont]))
        }

        textView.textStorage?.setAttributedString(output)
    }

    func showError(_ message: String) {
        textView?.string = "Error: \(message)"
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = link as? URL, url.scheme == Self.speakLinkScheme,
              let index = Int(url.absoluteString.dropFirst(Self.speakLinkScheme.count + 1)),
              let section = displayedSections[safe: index],
              let language = section.speechLanguage else { return false }

        SpeechPlayer.shared.toggle(section.body, language: language, id: index)
        return true
    }

    private func selectedTextSection() -> TranslationResult.Section? {
        guard !originalText.isEmpty else { return nil }
        let language = LanguageDetector.direction(for: originalText) == .englishToChinese ? "en-US" : "zh-CN"
        return .init(title: "SELECTED TEXT", body: originalText, speechLanguage: language)
    }

    func windowWillClose(_ notification: Notification) {
        SpeechPlayer.shared.stop()
    }

    private func closeExisting() {
        result = nil
        originalText = ""
        displayedSections = []
        panel?.close()
        panel = nil
        textView = nil
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
