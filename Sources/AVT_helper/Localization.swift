import Foundation

enum L {
    /// значение, которого нет ни у одного ключа: по нему видно, что перевод не нашёлся
    private static let missingMarker: String = "\u{0}absent"

    /// текст по ключу на выбранном языке; отсутствие перевода - ошибка сборки текстов, а не норма
    static func text(_ key: String, _ language: AppLanguage) -> String {
        let value: String = bundle(language).localizedString(forKey: key, value: missingMarker, table: nil)
        if value == missingMarker {
            assertionFailure("нет перевода для ключа \(key) на языке \(language.rawValue)")
            return key
        }
        return value
    }

    /// текст любой ошибки приложения на выбранном языке
    static func describe(_ error: Error, _ language: AppLanguage) -> String {
        switch error {
        case let subtitleError as SubtitleError:
            return subtitleError.message(language)
        case let updateError as UpdateError:
            return updateError.message(language)
        default:
            return error.localizedDescription
        }
    }

    /// подставляет значения в плейсхолдеры вида {token} локализованной строки
    static func format(_ key: String, _ language: AppLanguage, _ replacements: [String: String]) -> String {
        replacements.reduce(text(key, language)) { partial, pair in
            partial.replacingOccurrences(of: "{\(pair.key)}", with: pair.value)
        }
    }

    /// язык выбирается в самой программе, поэтому нужен именно бандл нужной локали,
    /// а не тот, который подобрала бы система
    static func bundle(_ language: AppLanguage) -> Bundle {
        guard let path: String = Bundle.module.path(forResource: language.rawValue, ofType: "lproj"),
            let bundle: Bundle = Bundle(path: path)
        else {
            return Bundle.module
        }
        return bundle
    }
}
