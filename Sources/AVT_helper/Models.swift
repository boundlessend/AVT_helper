import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case ru
    case en

    /// ключ хранения выбранного языка в UserDefaults / @AppStorage
    static let storageKey: String = "appLanguage"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ru:
            return "Русский"
        case .en:
            return "English"
        }
    }

    /// разбирает сырое значение из настроек, падая в русский по умолчанию
    static func resolve(_ raw: String?) -> AppLanguage {
        guard let raw: String = raw, let language: AppLanguage = AppLanguage(rawValue: raw) else {
            return .ru
        }
        return language
    }
}

enum AppLimits {
    /// максимальный размер импортируемого файла субтитров
    static let maxSubtitleFileBytes: UInt64 = 50 * 1024 * 1024
}

enum Roles {
    /// метка нераспознанной роли на выбранном языке
    static func unassigned(_ language: AppLanguage) -> String {
        L.text("role.unassigned", language)
    }

    /// проверяет, что имя совпадает с меткой нераспознанной роли на любом из языков
    static func isUnassigned(_ name: String) -> Bool {
        AppLanguage.allCases.contains { language in
            name.caseInsensitiveCompare(L.text("role.unassigned", language)) == .orderedSame
        }
    }
}

enum AppInfo {
    /// версия приложения из Info.plist собранного бандла
    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}

enum SubtitleSourceType: String, Sendable {
    case ass = "ASS"
    case ssa = "SSA"
    case srt = "SRT"
    case vtt = "VTT"
    case srp = "SRP"
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
    let sex: String

    /// роли для показа и экспорта: нераспознанная роль подставляется меткой нужного языка
    func displayRoles(_ language: AppLanguage) -> [String] {
        roles.isEmpty ? [Roles.unassigned(language)] : roles
    }
}

struct ImportedSubtitle: Sendable {
    let baseName: String
    let sourcePath: String
    let sourceType: SubtitleSourceType
    let lines: [SubtitleLine]

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

struct ExportSettings: Sendable {
    let exportAss: Bool
    let exportSrt: Bool
    let exportVtt: Bool
    let exportDocx: Bool
    let srtFullWithRoles: Bool
    let srtSeparateFiles: Bool
    let srtSeparateWithRoles: Bool
    let selectedRoles: Set<String>
}

enum VoiceGender: String, CaseIterable, Identifiable, Sendable {
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
enum WordHighlightColor: String, CaseIterable, Identifiable, Sendable {
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

struct VoiceConfig: Identifiable, Sendable {
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
