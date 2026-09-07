import Foundation

enum L {
    /// значение, которого нет ни у одного ключа: по нему видно, что перевод не нашёлся
    private static let missingMarker: String = "\u{0}absent"

    /// текст по ключу на выбранном языке; отсутствие перевода - ошибка сборки текстов, а не норма.
    /// assertionFailure вырезается из релизной сборки, поэтому там нужен запасной путь: перевод берётся
    /// у второго языка, и пользователь видит текст на чужом языке, а не служебный ключ
    static func text(_ key: String, _ language: AppLanguage) -> String {
        let value: String = bundle(language).localizedString(forKey: key, value: missingMarker, table: nil)
        if value != missingMarker {
            return value
        }
        assertionFailure("нет перевода для ключа \(key) на языке \(language.rawValue)")
        for fallback in AppLanguage.allCases where fallback != language {
            let spare: String = bundle(fallback).localizedString(forKey: key, value: missingMarker, table: nil)
            if spare != missingMarker {
                return spare
            }
        }
        return key
    }

    /// число с существительным в нужной форме. русский требует трёх форм, и выбирать их
    /// вручную нельзя: правило для 11-14 не совпадает с правилом для 1-4
    static func plural(_ key: String, _ language: AppLanguage, _ count: Int) -> String {
        let format: String = bundle(language).localizedString(forKey: key, value: missingMarker, table: nil)
        if format == missingMarker {
            assertionFailure("нет формы множественного числа для ключа \(key) на языке \(language.rawValue)")
            return "\(count)"
        }
        return String(format: format, locale: Locale(identifier: language.rawValue), count)
    }

    /// размер файла человеческими единицами: байты в сообщении об ошибке никто не читает.
    /// ByteCountFormatter локаль не принимает и берёт системную, поэтому единицы считает
    /// ByteCountFormatStyle: он принимает выбранный в программе язык и не требует перезапуска
    static func fileSize(_ bytes: UInt64, _ language: AppLanguage) -> String {
        return bytes.formatted(.byteCount(style: .file).locale(Locale(identifier: language.rawValue)))
    }

    /// текст любой ошибки приложения на выбранном языке
    static func describe(_ error: Error, _ language: AppLanguage) -> String {
        switch error {
        case let subtitleError as SubtitleError:
            return subtitleError.message(language)
        case let updateError as UpdateError:
            return updateError.message(language)
        case let partial as PartialExportError:
            return format(
                "error.partialExport", language,
                [
                    "cause": describe(partial.cause, language),
                    "files": plural("count.files", language, partial.created.count),
                ])
        case is CancellationError:
            return text("cancelled", language)
        default:
            return error.localizedDescription
        }
    }

    /// подставляет значения в плейсхолдеры вида {token} локализованной строки. замена идёт одним проходом,
    /// потому что последовательные replacingOccurrences подставляют значения и внутрь уже подставленного
    /// текста, а порядок обхода словаря к тому же не определён
    static func format(_ key: String, _ language: AppLanguage, _ replacements: [String: String]) -> String {
        let source: String = text(key, language)
        var result: String = ""
        var rest: Substring = source[...]
        while let open: String.Index = rest.firstIndex(of: "{") {
            let afterOpen: String.Index = rest.index(after: open)
            guard let close: String.Index = rest[afterOpen...].firstIndex(of: "}"),
                let value: String = replacements[String(rest[afterOpen..<close])]
            else {
                result += rest[..<afterOpen]
                rest = rest[afterOpen...]
                continue
            }
            result += rest[..<open]
            result += value
            rest = rest[rest.index(after: close)...]
        }
        return result + rest
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
