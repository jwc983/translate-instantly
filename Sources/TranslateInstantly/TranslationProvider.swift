import Foundation

enum TranslationProvider: String, CaseIterable {
    case gemini
    case deepseek

    var displayName: String {
        switch self {
        case .gemini: return "Gemini"
        case .deepseek: return "DeepSeek"
        }
    }

    private static let defaultsKey = "activeProvider"

    static var active: TranslationProvider {
        get {
            UserDefaults.standard.string(forKey: defaultsKey).flatMap(TranslationProvider.init(rawValue:)) ?? .gemini
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }
}
