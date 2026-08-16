import AppKit
import Foundation
import UniformTypeIdentifiers

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

/// «Открыть недавние» ведёт NSDocumentController: он следит за переименованиями файлов,
/// рисует значки и переживает переустановку, чего свой список в UserDefaults не умеет
@MainActor
final class RecentFiles: ObservableObject {
    static let shared: RecentFiles = RecentFiles()

    @Published private(set) var urls: [URL] = NSDocumentController.shared.recentDocumentURLs

    private init() {}

    func remember(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        urls = NSDocumentController.shared.recentDocumentURLs
    }

    func clear() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        urls = NSDocumentController.shared.recentDocumentURLs
    }
}

enum AppLimits {
    /// максимальный размер импортируемого файла субтитров
    static let maxSubtitleFileBytes: UInt64 = 50 * 1024 * 1024
    /// запас имени файла в байтах: 255 это предел файловой системы, остальное уходит
    /// на суффикс различения и расширение
    static let maxFileNameBytes: Int = 200
}

enum OutputFolder {
    /// папка выгрузки годится, только если путь абсолютный и ведёт в существующий каталог:
    /// относительный путь создал бы файлы неизвестно где
    static func isUsable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists: Bool = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return path.hasPrefix("/") && exists && isDirectory.boolValue
    }
}

enum Roles {
    /// метка нераспознанной роли на выбранном языке
    static func unassigned(_ language: AppLanguage) -> String {
        L.text("role.unassigned", language)
    }

    /// правда ли, что поле Name пришло из нашего же экспорта, где нераспознанная роль
    /// записана меткой. проверка нужна только импорту ASS: без неё круг через программу
    /// превращает отсутствие роли в роль с именем «Не назначено»
    static func isOwnPlaceholder(_ name: String) -> Bool {
        AppLanguage.allCases.contains { language in
            name.caseInsensitiveCompare(L.text("role.unassigned", language)) == .orderedSame
        }
    }
}

enum AppInfo {
    /// строка копирайта из Info.plist: в окне «О программе» она обязана совпадать с бандлом
    static var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
    }

    /// версия релиза: она же сравнивается с версией последнего релиза на GitHub
    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// номер сборки и её происхождение: «релиз» или коммит, из которого собрана эта копия
    static var buildLabel: String {
        let build: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let stage: String = Bundle.main.infoDictionary?["AVTBuildStage"] as? String ?? "dev"
        return stage == "release" ? build : "\(build), \(stage)"
    }
}

/// что программа берётся читать. один список на панель открытия, на перетаскивание
/// и на объявление типов документов в Info.plist
enum SubtitleFormats {
    static let extensions: [String] = ["ass", "ssa", "srt", "vtt", "srp"]

    static let contentTypes: [UTType] = extensions.compactMap { ext in UTType(filenameExtension: ext) }

    static func accepts(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    /// имя без разбора URL: перетаскивание сообщает его до того, как выдаст сам файл
    static func accepts(name: String) -> Bool {
        extensions.contains((name as NSString).pathExtension.lowercased())
    }
}

enum SubtitleSourceType: String, Sendable {
    case ass = "ASS"
    case ssa = "SSA"
    case srt = "SRT"
    case vtt = "VTT"
    case srp = "SRP"
}

/// пол персонажа, заявленный источником; SRP приносит его прямо в файле, остальные форматы не приносят вовсе
enum SourceSex: String, CaseIterable, Sendable {
    case male
    case female
    case unknown

    /// разбирает пометку пола SRP: там пишут «М», «МУЖ», «Ж», «ЖЕН»
    static func parse(_ input: String) -> SourceSex {
        switch input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "М", "M", "МУЖ":
            return .male
        case "Ж", "ЖЕН", "F":
            return .female
        default:
            return .unknown
        }
    }

    /// подсказка для разролёвки; неизвестный пол подсказки не даёт
    var voiceGender: VoiceGender? {
        switch self {
        case .male:
            return .male
        case .female:
            return .female
        case .unknown:
            return nil
        }
    }
}

struct SubtitleLine: Identifiable, Hashable, Sendable {
    let id: UUID
    let start: TimeInterval
    let end: TimeInterval
    /// очищенные уникальные роли реплики, вычисленные при импорте; пустой список означает нераспознанную роль
    let roles: [String]
    let text: String
    let style: String
    let effect: String
    let sex: SourceSex

    /// роли для показа и экспорта: нераспознанная роль подставляется меткой нужного языка
    func displayRoles(_ language: AppLanguage) -> [String] {
        roles.isEmpty ? [Roles.unassigned(language)] : roles
    }
}

/// заголовочные блоки исходного ASS, сохранённые дословно: без них экспорт ссылался бы
/// на стили, которых в файле нет, и плеер молча заменял бы их на Default
struct AssScript: Sendable {
    /// строки блока [Script Info] без самого заголовка
    let scriptInfo: [String]
    /// строки блока стилей без заголовка, включая строку Format
    let styles: [String]
    /// имя блока стилей: у SSA это [V4 Styles], у ASS [V4+ Styles]
    let stylesSection: String
}

struct ImportedSubtitle: Sendable {
    let baseName: String
    let sourcePath: String
    let sourceType: SubtitleSourceType
    let lines: [SubtitleLine]
    /// заголовок исходного ASS, если файл им был
    let assScript: AssScript?

    init(
        baseName: String,
        sourcePath: String,
        sourceType: SubtitleSourceType,
        lines: [SubtitleLine],
        assScript: AssScript? = nil
    ) {
        self.baseName = baseName
        self.sourcePath = sourcePath
        self.sourceType = sourceType
        self.lines = lines
        self.assScript = assScript
    }

    /// уникальные роли файла в алфавитном порядке, без учёта регистра
    func allRoles(_ language: AppLanguage) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for line in lines {
            for role in line.displayRoles(language) where seen.insert(role.lowercased()).inserted {
                result.append(role)
            }
        }
        return result.sorted { left, right in
            left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
    }
}

/// всё, что интерфейс знает о файле помимо самих реплик; считается один раз при импорте,
/// чтобы производные величины не разъезжались между собой
struct SubtitleDigest: Sendable {
    let roles: [String]
    let counts: [String: Int]
    let lineCount: Int
    let duration: TimeInterval
    /// имя, под которым в списке ролей стоят реплики без роли; nil означает, что таких реплик нет.
    /// это подставленная метка, а не роль из файла, поэтому цвет и голос ей не полагаются
    let placeholder: String?

    static let empty: SubtitleDigest = SubtitleDigest(roles: [], counts: [:], lineCount: 0, duration: 0, placeholder: nil)

    init(roles: [String], counts: [String: Int], lineCount: Int, duration: TimeInterval, placeholder: String? = nil) {
        self.roles = roles
        self.counts = counts
        self.lineCount = lineCount
        self.duration = duration
        self.placeholder = placeholder
    }

    init(subtitle: ImportedSubtitle, language: AppLanguage) {
        roles = subtitle.allRoles(language)
        counts = subtitle.lines.reduce(into: [String: Int]()) { result, line in
            for role in line.displayRoles(language) {
                result[role, default: 0] += 1
            }
        }
        lineCount = subtitle.lines.count
        duration = subtitle.lines.map { line in line.end }.max() ?? 0
        placeholder = subtitle.lines.contains { line in line.roles.isEmpty } ? Roles.unassigned(language) : nil
    }

    /// доля реплик роли от всего файла: она же длина полоски в списке ролей
    func share(of role: String) -> Double {
        lineCount == 0 ? 0 : Double(counts[role, default: 0]) / Double(lineCount)
    }
}

struct ExportSettings: Sendable {
    let exportAss: Bool
    let exportSrt: Bool
    let exportVtt: Bool
    let exportDocx: Bool
    let srtFullWithRoles: Bool
    let srtSeparateFiles: Bool
    let srtSeparateWithRoles: Bool
    let selectedRoles: Set<String>
    /// цвет маркера каждой роли: тот же, что в окне, поэтому лист и документ совпадают
    let roleHighlights: [String: WordHighlightColor]

    /// те же настройки для другого файла очереди: отметки и цвета принадлежат показанному файлу,
    /// а у соседней серии роли свои
    func forOtherFile(roles: Set<String>, highlights: [String: WordHighlightColor]) -> ExportSettings {
        ExportSettings(
            exportAss: exportAss,
            exportSrt: exportSrt,
            exportVtt: exportVtt,
            exportDocx: exportDocx,
            srtFullWithRoles: srtFullWithRoles,
            srtSeparateFiles: srtSeparateFiles,
            srtSeparateWithRoles: srtSeparateWithRoles,
            selectedRoles: roles,
            roleHighlights: highlights
        )
    }
}

enum VoiceGender: String, CaseIterable, Identifiable, Sendable, Codable {
    case male
    case female

    var id: String { rawValue }

    func shortTitle(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.male, .ru):
            return "м"
        case (.female, .ru):
            return "ж"
        case (.male, .en):
            return "m"
        case (.female, .en):
            return "f"
        }
    }

    func title(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.male, .ru):
            return "Мужской"
        case (.female, .ru):
            return "Женский"
        case (.male, .en):
            return "Male"
        case (.female, .en):
            return "Female"
        }
    }
}

/// rawValue совпадает со значением w:highlight в формате Word
enum WordHighlightColor: String, CaseIterable, Identifiable, Sendable, Codable {
    case yellow
    case green
    case cyan
    case magenta
    case blue
    case red
    case darkYellow
    case lightGray

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.yellow, .ru):
            return "Желтый"
        case (.green, .ru):
            return "Зеленый"
        case (.cyan, .ru):
            return "Бирюзовый"
        case (.magenta, .ru):
            return "Розовый"
        case (.blue, .ru):
            return "Синий"
        case (.red, .ru):
            return "Красный"
        case (.darkYellow, .ru):
            return "Темно-желтый"
        case (.lightGray, .ru):
            return "Серый"
        case (.yellow, .en):
            return "Yellow"
        case (.green, .en):
            return "Green"
        case (.cyan, .en):
            return "Cyan"
        case (.magenta, .en):
            return "Pink"
        case (.blue, .en):
            return "Blue"
        case (.red, .en):
            return "Red"
        case (.darkYellow, .en):
            return "Dark yellow"
        case (.lightGray, .en):
            return "Gray"
        }
    }

}

struct VoiceConfig: Identifiable, Sendable, Codable {
    let id: Int
    var gender: VoiceGender
    var color: WordHighlightColor
}

struct RoleGenderSetting: Identifiable, Sendable {
    let role: String
    var gender: VoiceGender

    var id: String { role }
}

struct RoleAssignmentResult: Sendable {
    let roleToVoice: [String: Int]
    let roleToHighlight: [String: WordHighlightColor]
}

struct VoiceRoleSummary: Sendable {
    let voice: VoiceConfig
    let roles: [String]
}
