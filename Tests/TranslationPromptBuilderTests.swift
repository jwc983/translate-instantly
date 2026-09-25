import Foundation

@main
enum TranslationPromptBuilderTests {
    static func main() {
        englishPromptRequestsIPAForOriginalText()
        englishResponseParsesPlainEnglishIPAAndChinese()
        chinesePromptDoesNotRequestIPA()
        englishParserKeepsWorkingWhenProviderOmitsIPA()
        readableSectionsHaveSpeechLanguages()
        englishPromptRequestsSimpleGrammarExplanation()
        chinesePromptDoesNotRequestGrammar()
        englishParserHandlesSectionsOutOfOrder()
        print("TranslationPromptBuilder tests passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("Test failed: \(message)\n", stderr)
            exit(1)
        }
    }

    private static func englishPromptRequestsIPAForOriginalText() {
        let prompt = TranslationPromptBuilder.prompt(
            for: "Hello world.",
            direction: .englishToChinese
        )

        expect(prompt.contains("IPA:"), "English prompt should contain the IPA marker")
        expect(prompt.contains("original English text"), "IPA should describe the original selection")
        expect(prompt.contains("General American"), "IPA should specify General American pronunciation")
        expect(prompt.hasSuffix("Text:\nHello world."), "Prompt should contain the selected text")
    }

    private static func englishResponseParsesPlainEnglishIPAAndChinese() {
        let result = TranslationPromptBuilder.parse(
            """
            PLAIN ENGLISH:
            Hello, world.

            IPA:
            /həˈloʊ wɝld/

            CHINESE:
            你好，世界。

            GRAMMAR:
            • Greeting: "Hello, world." is a set phrase
            """,
            direction: .englishToChinese
        )

        expect(result.sections.map(\.title) == ["PLAIN ENGLISH", "IPA", "中文", "GRAMMAR"], "Section titles should be ordered")
        expect(result.sections.map(\.body) == ["Hello, world.", "/həˈloʊ wɝld/", "你好，世界。", "• Greeting: \"Hello, world.\" is a set phrase"], "Section bodies should parse correctly")
    }

    private static func chinesePromptDoesNotRequestIPA() {
        let prompt = TranslationPromptBuilder.prompt(
            for: "你好",
            direction: .chineseToEnglish
        )

        expect(!prompt.contains("IPA:"), "Chinese selections should not request IPA")
    }

    private static func englishParserKeepsWorkingWhenProviderOmitsIPA() {
        let result = TranslationPromptBuilder.parse(
            """
            PLAIN ENGLISH:
            Hello.

            CHINESE:
            你好。
            """,
            direction: .englishToChinese
        )

        expect(result.sections.map(\.body) == ["Hello.", "", "你好。", ""], "Missing IPA and grammar should not break translation parsing")
    }

    private static func readableSectionsHaveSpeechLanguages() {
        let english = TranslationPromptBuilder.parse(
            "PLAIN ENGLISH:\nHi.\nIPA:\n/haɪ/\nCHINESE:\n你好。",
            direction: .englishToChinese
        )
        expect(english.sections.map(\.speechLanguage) == ["en-US", nil, "zh-CN", nil], "Plain English and Chinese should be readable aloud, IPA and grammar should not")

        let chinese = TranslationPromptBuilder.parse("ENGLISH:\nHello.", direction: .chineseToEnglish)
        expect(chinese.sections.first?.speechLanguage == "en-US", "English translation should be read in English")
    }

    private static func englishPromptRequestsSimpleGrammarExplanation() {
        let prompt = TranslationPromptBuilder.prompt(for: "I have lived here for years.", direction: .englishToChinese)

        expect(prompt.contains("GRAMMAR:"), "English prompt should contain the grammar marker")
        expect(prompt.contains("simply"), "Grammar explanation should be requested in simple terms")
        expect(prompt.contains("in plain, simple English. Use 2 to 4"), "Grammar explanation should be requested in English")
    }

    private static func chinesePromptDoesNotRequestGrammar() {
        let prompt = TranslationPromptBuilder.prompt(for: "你好", direction: .chineseToEnglish)

        expect(!prompt.contains("GRAMMAR:"), "Chinese selections should not request grammar")
    }

    private static func englishParserHandlesSectionsOutOfOrder() {
        let result = TranslationPromptBuilder.parse(
            "PLAIN ENGLISH:\nHi.\nGRAMMAR:\n• Greeting\nIPA:\n/haɪ/\nCHINESE:\n你好。",
            direction: .englishToChinese
        )

        expect(result.sections.map(\.body) == ["Hi.", "/haɪ/", "你好。", "• Greeting"], "Sections should parse regardless of the order the model uses")
    }
}
