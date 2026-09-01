import Foundation

enum VoiceGender: String, CaseIterable, Identifiable, Sendable, Codable {
    case male
    case female

    var id: String { rawValue }

    func shortTitle(_ language: AppLanguage) -> String {
        switch self {
        case .male:
            return L.text("gender.male.short", language)
        case .female:
            return L.text("gender.female.short", language)
        }
    }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .male:
            return L.text("gender.male", language)
        case .female:
            return L.text("gender.female", language)
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
        switch self {
        case .yellow:
            return L.text("color.yellow", language)
        case .green:
            return L.text("color.green", language)
        case .cyan:
            return L.text("color.cyan", language)
        case .magenta:
            return L.text("color.magenta", language)
        case .blue:
            return L.text("color.blue", language)
        case .red:
            return L.text("color.red", language)
        case .darkYellow:
            return L.text("color.darkYellow", language)
        case .lightGray:
            return L.text("color.lightGray", language)
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
