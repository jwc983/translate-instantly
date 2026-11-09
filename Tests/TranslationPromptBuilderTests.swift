import Foundation

@main
enum TranslationPromptBuilderTests {
    static func main() {
        englishPromptContainsSelectedText()
        englishResponseParsesAllSections()
        englishParserKeepsWorkingWhenProviderOmitsSections()
        readableSectionsHaveSpeechLanguages()
        englishPromptRequestsSimpleGrammarExplanation()
        chinesePromptDoesNotRequestGrammar()
        englishParserHandlesSectionsOutOfOrder()
        grammarBulletsAreNormalized()
        englishPromptRequestsAbbreviations()
        chinesePromptDoesNotRequestAbbreviations()
        abbreviationsNoneIsHidden()
        chinesePromptRequestsEnglishExplanation()
        chineseResponseParsesTranslationAndExplanation()
        chineseParserKeepsWorkingWithoutMarkers()
        print("TranslationPromptBuilder tests passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("Test failed: \(message)\n", stderr)
            exit(1)
        }
    }

    private static func englishPromptContainsSelectedText() {
        let prompt = TranslationPromptBuilder.prompt(for: "Hello world.", direction: .englishToChinese)

        expect(prompt.hasSuffix("Text:\nHello world."), "Prompt should contain the selected text")
    }

    private static func englishResponseParsesAllSections() {
        let result = TranslationPromptBuilder.parse(
            """
            PLAIN ENGLISH:
            Please reply soon.

            CHINESE:
            请尽快回复。

            ABBREVIATIONS:
            • ASAP: as soon as possible (尽快) - asks for a quick action.

            GRAMMAR:
            • Imperative: "Reply" gives a request
            """,
            direction: .englishToChinese
        )

        expect(result.sections.map(\.title) == ["PLAIN ENGLISH", "中文", "ABBREVIATIONS", "GRAMMAR"], "Section titles should be ordered")
        expect(
            result.sections.map(\.body) == [
                "Please reply soon.",
                "请尽快回复。",
                "• ASAP: as soon as possible (尽快) - asks for a quick action.",
                "• Imperative: \"Reply\" gives a request"
            ],
            "Section bodies should parse correctly"
        )
    }

    private static func englishParserKeepsWorkingWhenProviderOmitsSections() {
        let result = TranslationPromptBuilder.parse(
            """
            PLAIN ENGLISH:
            Hello.

            CHINESE:
            你好。
            """,
            direction: .englishToChinese
        )

        expect(result.sections.map(\.body) == ["Hello.", "你好。", "", ""], "Missing abbreviations and grammar should not break translation parsing")
    }

    private static func readableSectionsHaveSpeechLanguages() {
        let english = TranslationPromptBuilder.parse(
            "PLAIN ENGLISH:\nHi.\nCHINESE:\n你好。",
            direction: .englishToChinese
        )
        expect(english.sections.map(\.speechLanguage) == ["en-US", "zh-CN", nil, nil], "Plain English and Chinese should be readable aloud, abbreviations and grammar should not")

        let chinese = TranslationPromptBuilder.parse("ENGLISH:\nHello.", direction: .chineseToEnglish)
        expect(chinese.sections.first?.speechLanguage == "en-US", "English translation should be read in English")
    }

    private static func englishPromptRequestsSimpleGrammarExplanation() {
        let prompt = TranslationPromptBuilder.prompt(for: "I have lived here for years.", direction: .englishToChinese)

        expect(prompt.contains("GRAMMAR:"), "English prompt should contain the grammar marker")
        expect(prompt.contains("simply"), "Grammar explanation should be requested in simple terms")
        expect(prompt.contains("in plain, simple English. Write 2 to 4"), "Grammar explanation should be requested in English")
    }

    private static func chinesePromptDoesNotRequestGrammar() {
        let prompt = TranslationPromptBuilder.prompt(for: "你好", direction: .chineseToEnglish)

        expect(!prompt.contains("GRAMMAR:"), "Chinese selections should not request grammar")
    }

    private static func englishParserHandlesSectionsOutOfOrder() {
        let result = TranslationPromptBuilder.parse(
            "PLAIN ENGLISH:\nHi.\nGRAMMAR:\n• Greeting\nABBREVIATIONS:\n• FYI: for your information\nCHINESE:\n你好。",
            direction: .englishToChinese
        )

        expect(result.sections.map(\.body) == ["Hi.", "你好。", "• FYI: for your information", "• Greeting"], "Sections should parse regardless of the order the model uses")
    }

    private static func grammarBulletsAreNormalized() {
        let body = TranslationPromptBuilder.normalizeBulletList(
            """
            - **Present perfect**: "have lived" shows
              an action that is still true.

            2. Preposition: "for" gives a length of time.
            """
        )

        expect(
            body == "• Present perfect: \"have lived\" shows an action that is still true.\n• Preposition: \"for\" gives a length of time.",
            "Bullets should be unified, unwrapped, and stripped of Markdown"
        )
    }

    private static func englishPromptRequestsAbbreviations() {
        let prompt = TranslationPromptBuilder.prompt(for: "Reply ASAP.", direction: .englishToChinese)

        expect(prompt.contains("ABBREVIATIONS:"), "English prompt should contain the abbreviations marker")
        expect(prompt.contains("write only \"None\""), "Prompt should say what to write when there are no abbreviations")
    }

    private static func chinesePromptDoesNotRequestAbbreviations() {
        let prompt = TranslationPromptBuilder.prompt(for: "你好", direction: .chineseToEnglish)

        expect(!prompt.contains("ABBREVIATIONS:"), "Chinese selections should not request abbreviations")
    }

    private static func abbreviationsNoneIsHidden() {
        for none in ["None", "none.", "NONE"] {
            let result = TranslationPromptBuilder.parse(
                "PLAIN ENGLISH:\nHi.\nCHINESE:\n你好。\nABBREVIATIONS:\n\(none)\nGRAMMAR:\n• Greeting",
                direction: .englishToChinese
            )
            expect(result.sections[2].body.isEmpty, "\"\(none)\" should become an empty, hidden abbreviations section")
        }
    }

    private static func chinesePromptRequestsEnglishExplanation() {
        let prompt = TranslationPromptBuilder.prompt(for: "马马虎虎", direction: .chineseToEnglish)

        expect(prompt.contains("EXPLANATION:"), "Chinese prompt should contain the explanation marker")
        expect(prompt.contains("in plain, simple English"), "Explanation should be requested in simple English")
    }

    private static func chineseResponseParsesTranslationAndExplanation() {
        let result = TranslationPromptBuilder.parse(
            """
            ENGLISH:
            So-so.

            EXPLANATION:
            - **马马虎虎 (mǎmǎhūhū)**: an idiom meaning "so-so".
            """,
            direction: .chineseToEnglish
        )

        expect(result.sections.map(\.title) == ["ENGLISH", "EXPLANATION"], "Chinese sections should be ordered")
        expect(
            result.sections.map(\.body) == ["So-so.", "• 马马虎虎 (mǎmǎhūhū): an idiom meaning \"so-so\"."],
            "Chinese section bodies should parse and bullets should be normalized"
        )
        expect(result.sections.map(\.speechLanguage) == ["en-US", nil], "Only the translation should be read aloud")
    }

    private static func chineseParserKeepsWorkingWithoutMarkers() {
        let result = TranslationPromptBuilder.parse("Hello.", direction: .chineseToEnglish)

        expect(result.sections.map(\.body) == ["Hello.", ""], "An unlabeled reply should be shown as the translation, with the explanation hidden")
    }
}
