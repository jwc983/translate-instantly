import AVFoundation

final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechPlayer()

    /// Called on the main thread whenever playback starts or stops, so the UI
    /// can flip its play/stop controls.
    var onStateChange: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private(set) var speakingID: Int?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Starts reading `text`, or stops if `id` is the one already playing.
    func toggle(_ text: String, language: String, id: Int) {
        if speakingID == id {
            stop()
            return
        }

        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice(for: language)
        speakingID = id
        currentUtterance = utterance
        synthesizer.speak(utterance)
        notify()
    }

    func stop() {
        guard speakingID != nil else { return }
        speakingID = nil
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        notify()
    }

    // The default voice for a language is often the robotic compact one, so
    // prefer any Premium/Enhanced (neural) voice the user has downloaded in
    // System Settings › Accessibility › Spoken Content.
    private static func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        return candidates.max(by: { $0.quality.rawValue < $1.quality.rawValue })
            ?? AVSpeechSynthesisVoice(language: language)
    }

    private func notify() {
        DispatchQueue.main.async { self.onStateChange?() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(utterance)
    }

    private func finished(_ utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            // Switching sections cancels the old utterance, and that callback
            // arrives after the new one has started; ignore it.
            guard utterance === self.currentUtterance else { return }
            self.currentUtterance = nil
            self.speakingID = nil
            self.onStateChange?()
        }
    }
}
