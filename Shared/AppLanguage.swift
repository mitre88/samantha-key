import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case italian = "it"
    case korean = "ko"
    case portuguese = "pt-BR"
    case chinese = "zh-Hans"
    case japanese = "ja"

    var id: String { rawValue }

    static func resolved(from rawValue: String?) -> AppLanguage {
        guard let rawValue, let language = AppLanguage(rawValue: rawValue) else { return .english }
        return language
    }

    var displayName: LocalizedStringKey {
        switch self {
        case .english: "language.english"
        case .spanish: "language.spanish"
        case .french: "language.french"
        case .italian: "language.italian"
        case .korean: "language.korean"
        case .portuguese: "language.portuguese"
        case .chinese: "language.chinese"
        case .japanese: "language.japanese"
        }
    }

    var plainName: String {
        switch self {
        case .english: "English"
        case .spanish: "Español"
        case .french: "Français"
        case .italian: "Italiano"
        case .korean: "한국어"
        case .portuguese: "Português"
        case .chinese: "中文"
        case .japanese: "日本語"
        }
    }

    var realtimeLabel: String {
        switch self {
        case .english: "English"
        case .spanish: "Spanish"
        case .french: "French"
        case .italian: "Italian"
        case .korean: "Korean"
        case .portuguese: "Portuguese"
        case .chinese: "Simplified Chinese"
        case .japanese: "Japanese"
        }
    }

    var realtimeTranslationCode: String {
        switch self {
        case .english: "en"
        case .spanish: "es"
        case .french: "fr"
        case .italian: "it"
        case .korean: "ko"
        case .portuguese: "pt"
        case .chinese: "zh"
        case .japanese: "ja"
        }
    }
}
