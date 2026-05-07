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
}

enum SubtitleFormat: String, CaseIterable, Identifiable {
    case ass = "ASS"
    case srt = "SRT"
    case vtt = "VTT"
    case docx = "DOCX"

    var id: String { rawValue }
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
        return uniqueRoles.isEmpty ? ["Не назначено"] : uniqueRoles
    }
}

struct ImportedSubtitle {
    let sourcePath: String
    let baseName: String
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
    case male = "Мужской"
    case female = "Женский"

    var id: String { rawValue }

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

enum WordHighlightColor: String, CaseIterable, Identifiable {
    case yellow = "Желтый"
    case green = "Зеленый"
    case cyan = "Бирюзовый"
    case magenta = "Розовый"
    case blue = "Синий"
    case red = "Красный"
    case darkYellow = "Темно-желтый"
    case lightGray = "Серый"

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

    var wordValue: String {
        switch self {
        case .yellow:
            return "yellow"
        case .green:
            return "green"
        case .cyan:
            return "cyan"
        case .magenta:
            return "magenta"
        case .blue:
            return "blue"
        case .red:
            return "red"
        case .darkYellow:
            return "darkYellow"
        case .lightGray:
            return "lightGray"
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
