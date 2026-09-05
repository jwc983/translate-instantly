import AppKit

final class TranslationPanel {
    static let shared = TranslationPanel()

    private var panel: NSPanel?
    private var textView: NSTextView?

    func show(loadingFor originalText: String = "") {
        closeExisting()

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

        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = panel.contentView!.bounds
        scrollView.autoresizingMask = [.width, .height]
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.string = "Translating…"
        textView.textContainerInset = NSSize(width: 14, height: 14)

        panel.contentView?.addSubview(scrollView)
        panel.orderFrontRegardless()

        self.panel = panel
        self.textView = textView
    }

    func update(with result: TranslationResult) {
        guard let textView = textView else { return }

        let headerFont = NSFont.boldSystemFont(ofSize: 12)
        let headerColor = NSColor.secondaryLabelColor
        let bodyFont = NSFont.systemFont(ofSize: 15)

        let output = NSMutableAttributedString()
        for section in result.sections where !section.body.isEmpty {
            if output.length > 0 {
                output.append(NSAttributedString(string: "\n\n"))
            }
            output.append(NSAttributedString(string: section.title, attributes: [.font: headerFont, .foregroundColor: headerColor]))
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

    private func closeExisting() {
        panel?.close()
        panel = nil
        textView = nil
    }
}
