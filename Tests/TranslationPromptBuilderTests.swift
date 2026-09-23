import Foundation

@main
enum TranslationPromptBuilderTests {
    static func main() {
        englishPromptRequestsIPAForOriginalText()
        englishResponseParsesPlainEnglishIPAAndChinese()
        chinesePromptDoesNotRequestIPA()
        englishParserKeepsWorkingWhenProviderOmitsIPA()
        readableSectionsHaveSpeechLanguages()
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
            """,
            direction: .englishToChinese
        )

        expect(result.sections.map(\.title) == ["PLAIN ENGLISH", "IPA", "中文"], "Section titles should be ordered")
        expect(result.sections.map(\.body) == ["Hello, world.", "/həˈloʊ wɝld/", "你好，世界。"], "Section bodies should parse correctly")
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

        expect(result.sections.map(\.body) == ["Hello.", "", "你好。"], "Missing IPA should not break translation parsing")
    }

    private static func readableSectionsHaveSpeechLanguages() {
        let english = TranslationPromptBuilder.parse(
            "PLAIN ENGLISH:\nHi.\nIPA:\n/haɪ/\nCHINESE:\n你好。",
            direction: .englishToChinese
        )
        expect(english.sections.map(\.speechLanguage) == ["en-US", nil, "zh-CN"], "Plain English and Chinese should be readable aloud, IPA should not")

        let chinese = TranslationPromptBuilder.parse("ENGLISH:\nHello.", direction: .chineseToEnglish)
        expect(chinese.sections.first?.speechLanguage == "en-US", "English translation should be read in English")
    }
}
