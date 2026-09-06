import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en", simplifiedChinese = "zh-Hans", traditionalChinese = "zh-Hant"
    case japanese = "ja", spanish = "es"

    static let preferenceKey = "uselesspet.language"
    static func resolve(_ code: String?) -> Self { code.flatMap(Self.init(rawValue:)) ?? .english }
    static var current: Self { resolve(UserDefaults.standard.string(forKey: preferenceKey)) }
    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .japanese: return "日本語"
        case .spanish: return "Español"
        }
    }
}

enum L10nKey: String, CaseIterable {
    case back
    case settings
    case chooseTitle
    case homeSubtitle
    case reconnecting
    case petAction
    case chooseAction
    case hidePet
    case showPet
    case summonPet
    case pickerOffline
    case pickerSubtitle
    case sizeTitle
    case sizeSmall
    case sizeMedium
    case sizeLarge
    case headTracking
    case quit
    case switchTo
    case selected
    case notSelected
    case disconnected
    case switchFailed
    case language
    case languageHint
    case reactionJoy
    case reactionDelight
    case reactionSurprise
    case reactionSilly
    case reactionCuddle
}

enum L10n {
    static let appName = "UselessPet"
    static func text(_ key: L10nKey, language: AppLanguage = .current, name: String = "") -> String {
        let fallback = resourceBundle(for: .english)?.localizedString(forKey: key.rawValue, value: key.rawValue, table: nil) ?? key.rawValue
        return (resourceBundle(for: language)?.localizedString(forKey: key.rawValue, value: fallback, table: nil) ?? fallback)
            .replacingOccurrences(of: "{app}", with: appName)
            .replacingOccurrences(of: "{name}", with: name)
    }
    static func resourceBundle(for language: AppLanguage) -> Bundle? {
        // SwiftPM normalizes locale directory names, including zh-Hans/Hant.
        for code in [language.rawValue, language.rawValue.lowercased()] {
            if let path = Bundle.uselesspetResources.path(forResource: code, ofType: "lproj") {
                return Bundle(path: path)
            }
        }
        return nil
    }
}
