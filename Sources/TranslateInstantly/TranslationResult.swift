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
    private static let chineseMarker = "CHINESE:"
    private static let grammarMarker = "GRAMMAR:"
    private static let abbreviationsMarker = "ABBREVIATIONS:"
    private static let englishMarker = "ENGLISH:"
    private static let explanationMarker = "EXPLANATION:"

    private static let englishToChineseInstructions = """
    You are a translation assistant. The user selected a piece of English text.
    Respond with exactly four labeled sections, in this order, and nothing else:

    \(plainEnglishMarker)
    Rewrite the text in plain, simple English: easy vocabulary, short sentences, same meaning.

    \(chineseMarker)
    A natural Simplified Chinese translation of the original text. Give only the translation, with no explanation.

    \(abbreviationsMarker)
    Explain every abbreviation, acronym, initialism and short form in the original text (for example "ASAP", "e.g.", "API", "FYI", "Dr."). Write one bullet per abbreviation, one per line, in the form "• ABBR: full form (Simplified Chinese meaning) - short explanation in plain, simple English", for example "• ASAP: as soon as possible (尽快) - used to ask for something to be done quickly." Keep each explanation under 20 words. Do not use Markdown or blank lines. If the text has no abbreviations, write only "None".

    \(grammarMarker)
    Explain the key grammar of the original text simply, for an English learner, in plain, simple English. Write 2 to 4 bullet points, one per line, each in the form "• Grammar point: short explanation", for example "• Present perfect: "have lived" shows an action that started in the past and is still true." Keep each explanation under 25 words and quote the words it applies to. Do not use Markdown or blank lines. Skip anything too basic to be worth noting. If the text is a single word, give its part of speech and one common usage instead.
    """

    private static let chineseToEnglishInstructions = """
    You are a translation assistant. The user selected a piece of Chinese text.
    Respond with exactly two labeled sections, in this order, and nothing else:

    \(englishMarker)
    A natural English translation of the original text.

    \(explanationMarker)
    Explain the meaning of the original text in plain, simple English, for an English speaker learning Chinese. Write 2 to 4 bullet points, one per line, each in the form "• Chinese words (pinyin): short explanation", for example "• 马马虎虎 (mǎmǎhūhū): an idiom meaning "so-so" or "careless"; word for word it is "horse horse tiger tiger"." Focus on idioms, set phrases, cultural references, and words whose meaning is not clear from the translation. Keep each explanation under 25 words. Do not use Markdown or blank lines. If the text is a single word, give its part of speech and one common usage instead.
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

            let bodies = splitSections(trimmed, markers: [plainEnglishMarker, chineseMarker, abbreviationsMarker, grammarMarker])
            // Text before the first marker is treated as the plain-English
            // rewrite when the model leaves off its label.
            let plainEnglish = bodies[plainEnglishMarker] ?? bodies[""] ?? ""

            return TranslationResult(sections: [
                .init(title: "PLAIN ENGLISH", body: plainEnglish, speechLanguage: "en-US"),
                .init(title: "中文", body: bodies[chineseMarker] ?? "", speechLanguage: "zh-CN"),
                .init(title: "ABBREVIATIONS", body: abbreviationsBody(bodies[abbreviationsMarker] ?? "")),
                .init(title: "GRAMMAR", body: normalizeBulletList(bodies[grammarMarker] ?? ""))
            ])

        case .chineseToEnglish:
            let bodies = splitSections(trimmed, markers: [englishMarker, explanationMarker])
            // Text before the first marker is treated as the translation
            // when the model leaves off its label.
            let english = bodies[englishMarker] ?? bodies[""] ?? ""
            return TranslationResult(sections: [
                .init(title: "ENGLISH", body: english, speechLanguage: "en-US"),
                .init(title: "EXPLANATION", body: normalizeBulletList(bodies[explanationMarker] ?? ""))
            ])
        }
    }

    /// The model is told to write "None" when there are no abbreviations;
    /// turning that into an empty body makes the panel hide the section.
    private static func abbreviationsBody(_ body: String) -> String {
        let cleaned = body.trimmingCharacters(in: CharacterSet(charactersIn: " .\n"))
        if cleaned.isEmpty || cleaned.caseInsensitiveCompare("None") == .orderedSame {
            return ""
        }
        return normalizeBulletList(body)
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

    /// Models don't always stick to the requested bullet format, so this
    /// turns "-", "*" and numbered items into "• " lines, strips Markdown
    /// emphasis, drops blank lines, and joins wrapped lines onto their bullet.
    static func normalizeBulletList(_ body: String) -> String {
        var items: [String] = []
        for rawLine in body.components(separatedBy: .newlines) {
            var line = rawLine
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if let markerRange = line.range(of: #"^([•\-*·]|\d+[.)])\s*"#, options: .regularExpression) {
                line.removeSubrange(markerRange)
                items.append("• " + line)
            } else if let last = items.last, last.hasPrefix("• ") {
                items[items.count - 1] = last + " " + line
            } else {
                items.append(line)
            }
        }
        return items.joined(separator: "\n")
    }
}
