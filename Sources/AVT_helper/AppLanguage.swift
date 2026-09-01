import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case ru
    case en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ru:
            return "Русский"
        case .en:
            return "English"
        }
    }

    /// язык, который выбрала система из локализаций приложения: он же язык меню, панелей и алертов,
    /// поэтому интерфейс обязан следовать за ним, а не за своим представлением о системных настройках
    static var systemDefault: AppLanguage {
        let preferred: [String] = Bundle.main.preferredLocalizations + Locale.preferredLanguages
        guard let first: String = preferred.first else {
            return .en
        }
        return first.hasPrefix("ru") ? .ru : .en
    }

    /// разбирает сырое значение из настроек; всё неизвестное означает «как в системе»
    static func resolve(_ raw: String?) -> AppLanguage {
        LanguagePreference.resolve(raw).language
    }
}

/// выбор языка в настройках. системные меню, панель открытия файла и кнопки алертов рисует AppKit,
/// и он читает AppleLanguages домена приложения, поэтому выбор записывается туда же:
/// иначе половина окна остаётся на языке системы
enum LanguagePreference: String, CaseIterable, Identifiable {
    case system
    case ru
    case en

    /// ключ хранения выбранного языка в UserDefaults / @AppStorage
    static let storageKey: String = "appLanguage"
    /// ключ, по которому AppKit выбирает локализацию бандла
    static let appleLanguagesKey: String = "AppleLanguages"
    /// что мы записали в него в прошлый раз. читать сам AppleLanguages для сравнения нельзя:
    /// при отсутствии значения в домене программы UserDefaults отдаёт общесистемное,
    /// и «как в системе» вечно выглядело бы как несохранённая перемена
    private static let appliedKey: String = "appliedAppleLanguages"

    var id: String { rawValue }

    static func resolve(_ raw: String?) -> LanguagePreference {
        guard let raw: String = raw, let preference: LanguagePreference = LanguagePreference(rawValue: raw) else {
            return .system
        }
        return preference
    }

    var language: AppLanguage {
        switch self {
        case .system:
            return AppLanguage.systemDefault
        case .ru:
            return .ru
        case .en:
            return .en
        }
    }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .system:
            return L.text("settings.language.system", language)
        case .ru:
            return AppLanguage.ru.title
        case .en:
            return AppLanguage.en.title
        }
    }

    /// значение AppleLanguages для этого выбора; nil означает, что ключ надо убрать и отдать выбор системе
    var appleLanguages: [String]? {
        switch self {
        case .system:
            return nil
        case .ru:
            return ["ru"]
        case .en:
            return ["en"]
        }
    }

    /// правда ли, что после перезапуска язык интерфейса изменится: только это стоит перезапуска
    func needsRelaunch(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.stringArray(forKey: Self.appliedKey) != appleLanguages
    }

    func apply(_ defaults: UserDefaults = .standard) {
        guard let languages: [String] = appleLanguages else {
            defaults.removeObject(forKey: Self.appleLanguagesKey)
            defaults.removeObject(forKey: Self.appliedKey)
            return
        }
        defaults.set(languages, forKey: Self.appleLanguagesKey)
        defaults.set(languages, forKey: Self.appliedKey)
    }
}
