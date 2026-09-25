import Foundation

struct TranslationResult {
    struct Section {
        let title: String
        let body: String
        /// BCP-47 code used to read the body aloud; nil hides the play button.
        var speechLanguage: String? = nil
    }

    let sections: [Section]
}

enum TranslationDirection {
    case englishToChinese
    case chineseToEnglish
}

enum LanguageDetector {
    // Selection could be pasted from anywhere and mix scripts (code comments,
    // quoted foreign words, etc.), so this counts CJK ideographs against Latin
    // letters rather than requiring the text to be purely one script.
    static func direction(for text: String) -> TranslationDirection {
        var chineseCount = 0
        var latinCount = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF:
                chineseCount += 1
            case 0x0041...0x005A, 0x0061...0x007A:
                latinCount += 1
            default:
                break
            }
        }
        return chineseCount > latinCount ? .chineseToEnglish : .englishToChinese
    }
}

enum TranslationPromptBuilder {
    private static let plainEnglishMarker = "PLAIN ENGLISH:"
    private static let ipaMarker = "IPA:"
    private static let chineseMarker = "CHINESE:"
    private static let grammarMarker = "GRAMMAR:"
    private static let englishMarker = "ENGLISH:"

    private static let englishToChineseInstructions = """
    You are a translation assistant. The user selected a piece of English text.
    Respond with exactly four labeled sections, in this order, and nothing else:

    \(plainEnglishMarker)
    Rewrite the text in plain, simple English: easy vocabulary, short sentences, same meaning.

    \(ipaMarker)
    Transcribe the original English text in International Phonetic Alphabet (IPA). Use a natural General American pronunciation, put the transcription between slashes, and preserve sentence boundaries. Do not explain the transcription.

    \(chineseMarker)
    A natural Simplified Chinese translation of the original text.

    \(grammarMarker)
    Explain the key grammar of the original text simply, for an English learner, in plain, simple English. Use 2 to 4 short bullet points, each starting with "• ". Name each grammar point (for example present perfect or relative clause) and quote the words it applies to. Skip anything too basic to be worth noting. If the text is a single word, give its part of speech and one common usage instead.
    """

    private static let chineseToEnglishInstructions = """
    You are a translation assistant. The user selected a piece of Chinese text.
    Respond with exactly one labeled section, and nothing else:

    \(englishMarker)
    A natural English translation of the original text.
    """

    static func direction(for text: String) -> TranslationDirection {
        LanguageDetector.direction(for: text)
    }

    static func prompt(for text: String, direction: TranslationDirection) -> String {
        let instructions = direction == .englishToChinese ? englishToChineseInstructions : chineseToEnglishInstructions
        return "\(instructions)\n\nText:\n\(text)"
    }

    // Falls back to treating the whole response as a single section if the
    // model doesn't follow the requested format, so a malformed reply still
    // shows something useful instead of an empty panel.
    static func parse(_ raw: String, direction: TranslationDirection) -> TranslationResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        switch direction {
        case .englishToChinese:
            guard trimmed.range(of: chineseMarker, options: .caseInsensitive) != nil else {
                return TranslationResult(sections: [.init(title: "中文", body: trimmed, speechLanguage: "zh-CN")])
            }

            let bodies = splitSections(trimmed, markers: [plainEnglishMarker, ipaMarker, chineseMarker, grammarMarker])
            // Text before the first marker is treated as the plain-English
            // rewrite when the model leaves off its label.
            let plainEnglish = bodies[plainEnglishMarker] ?? bodies[""] ?? ""

            return TranslationResult(sections: [
                .init(title: "PLAIN ENGLISH", body: plainEnglish, speechLanguage: "en-US"),
                .init(title: "IPA", body: bodies[ipaMarker] ?? ""),
                .init(title: "中文", body: bodies[chineseMarker] ?? "", speechLanguage: "zh-CN"),
                .init(title: "GRAMMAR", body: bodies[grammarMarker] ?? "")
            ])

        case .chineseToEnglish:
            var englishSection = trimmed
            if let markerRange = trimmed.range(of: englishMarker, options: .caseInsensitive) {
                englishSection = String(trimmed[markerRange.upperBound...])
            }
            return TranslationResult(sections: [
                .init(title: "ENGLISH", body: englishSection.trimmingCharacters(in: .whitespacesAndNewlines), speechLanguage: "en-US")
            ])
        }
    }

    /// Splits `text` at each marker's first occurrence, in whatever order the
    /// markers appear. Keys are the markers; "" holds any text before the
    /// first marker.
    private static func splitSections(_ text: String, markers: [String]) -> [String: String] {
        let found = markers
            .compactMap { marker in text.range(of: marker, options: .caseInsensitive).map { (marker, $0) } }
            .sorted { $0.1.lowerBound < $1.1.lowerBound }

        var bodies: [String: String] = [:]
        let leadingEnd = found.first?.1.lowerBound ?? text.endIndex
        bodies[""] = String(text[text.startIndex..<leadingEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        for (index, (marker, range)) in found.enumerated() {
            let end = index + 1 < found.count ? found[index + 1].1.lowerBound : text.endIndex
            bodies[marker] = String(text[range.upperBound..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return bodies
    }
}
