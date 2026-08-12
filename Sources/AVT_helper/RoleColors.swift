import SwiftUI

enum RoleColors {
    /// цвета ролей до разролёвки: голосов ещё нет, поэтому цвет нужен только чтобы различать роли в листе
    static func automatic(roles: [String]) -> [String: WordHighlightColor] {
        let palette: [WordHighlightColor] = WordHighlightColor.allCases
        var result: [String: WordHighlightColor] = [:]
        var index: Int = 0
        for role in roles where !Roles.isUnassigned(role) {
            result[role] = palette[index % palette.count]
            index += 1
        }
        return result
    }

    /// экранный маркер: заливка мягче печатной, чтобы тёмный текст поверх неё оставался читаемым
    static func swatch(_ color: WordHighlightColor) -> Color {
        switch color {
        case .yellow:
            return Color(red: 1.0, green: 0.882, blue: 0.302)
        case .green:
            return Color(red: 0.576, green: 0.910, blue: 0.643)
        case .cyan:
            return Color(red: 0.475, green: 0.886, blue: 0.949)
        case .magenta:
            return Color(red: 1.0, green: 0.659, blue: 0.867)
        case .blue:
            return Color(red: 0.659, green: 0.753, blue: 1.0)
        case .red:
            return Color(red: 1.0, green: 0.624, blue: 0.592)
        case .darkYellow:
            return Color(red: 0.843, green: 0.761, blue: 0.416)
        case .lightGray:
            return Color(red: 0.824, green: 0.831, blue: 0.839)
        }
    }

    /// текст поверх маркера всегда тёмный: так же он выглядит и в DOCX, и это не зависит от схемы системы
    static let inkOnSwatch: Color = Color(red: 0.08, green: 0.09, blue: 0.11)
}
