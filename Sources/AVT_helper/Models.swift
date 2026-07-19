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

    /// текущий язык приложения, прочитанный напрямую из настроек
    static var current: AppLanguage {
        resolve(UserDefaults.standard.string(forKey: storageKey))
    }
}

enum AppLimits {
    /// максимальный размер импортируемого файла субтитров
    static let maxSubtitleFileBytes: UInt64 = 50 * 1024 * 1024
}

enum Roles {
    /// каноническое имя для нераспознанной роли на текущем языке приложения
    static var unassigned: String {
        L.text("role.unassigned", AppLanguage.current)
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

enum SubtitleSourceType: String {
    case ass = "ASS"
    case ssa = "SSA"
    case srt = "SRT"
    case vtt = "VTT"
    case srp = "SRP"
}

struct SubtitleLine: Identifiable, Hashable {
    let id: UUID
    let start: TimeInterval
    let end: TimeInterval
    let role: String
    let roles: [String]
    let text: String
    let style: String
    let effect: String
    let sex: String

    var effectiveRoles: [String] {
        let sourceRoles: [String] = roles.isEmpty ? [role] : roles
        let uniqueRoles: [String] = sourceRoles.reduce(into: [String]()) { result, item in
            let normalized: String = TextTools.cleanRoleName(item)
            let exists: Bool = result.contains { current in
                current.caseInsensitiveCompare(normalized) == .orderedSame
            }
            if !normalized.isEmpty && !exists {
                result.append(normalized)
            }
        }
        return uniqueRoles.isEmpty ? [Roles.unassigned] : uniqueRoles
    }
}

struct ImportedSubtitle {
    let baseName: String
    let sourcePath: String
    let sourceType: SubtitleSourceType
    let lines: [SubtitleLine]

    var allRoles: [String] {
        lines
            .flatMap { line in line.effectiveRoles }
            .reduce(into: [String]()) { result, role in
                let exists: Bool = result.contains { current in
                    current.caseInsensitiveCompare(role) == .orderedSame
                }
                if !exists {
                    result.append(role)
                }
            }
            .sorted { left, right in
                left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }
    }
}

struct ExportSettings {
    let exportAss: Bool
    let exportSrt: Bool
    let exportVtt: Bool
    let exportDocx: Bool
    let srtFullWithRoles: Bool
    let srtSeparateFiles: Bool
    let srtSeparateWithRoles: Bool
    let selectedRoles: Set<String>
}

enum VoiceGender: String, CaseIterable, Identifiable {
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
enum WordHighlightColor: String, CaseIterable, Identifiable {
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

struct VoiceConfig: Identifiable {
    let id: Int
    var gender: VoiceGender
    var color: WordHighlightColor
}

struct RoleGenderSetting: Identifiable {
    let role: String
    var gender: VoiceGender

    var id: String { role }
}

struct RoleAssignmentResult {
    let roleToVoice: [String: Int]
    let roleToHighlight: [String: WordHighlightColor]
}

struct VoiceRoleSummary {
    let voice: VoiceConfig
    let roles: [String]
}
