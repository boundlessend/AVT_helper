import Foundation

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
    /// слой и поля отступов строки Dialogue: их приносит только ASS, и без них круг через программу
    /// затирал бы надписи и караоке нулями
    let layer: Int
    let marginL: Int
    let marginR: Int
    let marginV: Int

    init(
        id: UUID,
        start: TimeInterval,
        end: TimeInterval,
        roles: [String],
        text: String,
        style: String,
        effect: String,
        sex: SourceSex,
        layer: Int = 0,
        marginL: Int = 0,
        marginR: Int = 0,
        marginV: Int = 0
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.roles = roles
        self.text = text
        self.style = style
        self.effect = effect
        self.sex = sex
        self.layer = layer
        self.marginL = marginL
        self.marginR = marginR
        self.marginV = marginV
    }

    /// роли для показа и экспорта: нераспознанная роль подставляется меткой нужного языка
    func displayRoles(_ language: AppLanguage) -> [String] {
        roles.isEmpty ? [Roles.unassigned(language)] : roles
    }

    /// та же реплика с другим набором ролей: имена ролей сводятся к одному написанию уже после разбора
    func withRoles(_ newRoles: [String]) -> SubtitleLine {
        SubtitleLine(
            id: id,
            start: start,
            end: end,
            roles: newRoles,
            text: text,
            style: style,
            effect: effect,
            sex: sex,
            layer: layer,
            marginL: marginL,
            marginR: marginR,
            marginV: marginV
        )
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
    /// сколько блоков файла разобрать не удалось: без этого числа частично прочитанный файл
    /// выглядит как файл, где этих реплик и не было
    let skippedBlocks: Int

    init(
        baseName: String,
        sourcePath: String,
        sourceType: SubtitleSourceType,
        lines: [SubtitleLine],
        assScript: AssScript? = nil,
        skippedBlocks: Int = 0
    ) {
        self.baseName = baseName
        self.sourcePath = sourcePath
        self.sourceType = sourceType
        self.lines = lines
        self.assScript = assScript
        self.skippedBlocks = skippedBlocks
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

    /// счётчики без подставленной метки «нет роли»: голос и цвет ей не полагаются,
    /// поэтому разролёвка считает только по названным ролям
    var namedCounts: [String: Int] {
        counts.filter { role, _ in role != placeholder }
    }

    /// доля реплик роли от всего файла: она же длина полоски в списке ролей
    func share(of role: String) -> Double {
        lineCount == 0 ? 0 : Double(counts[role, default: 0]) / Double(lineCount)
    }
}

extension SubtitleDigest {
    /// сводка по разобранному файлу; в extension, чтобы у структуры остался её же почленный init
    init(subtitle: ImportedSubtitle, language: AppLanguage) {
        self.init(
            roles: subtitle.allRoles(language),
            counts: subtitle.lines.reduce(into: [String: Int]()) { result, line in
                for role in line.displayRoles(language) {
                    result[role, default: 0] += 1
                }
            },
            lineCount: subtitle.lines.count,
            duration: subtitle.lines.map { line in line.end }.max() ?? 0,
            placeholder: subtitle.lines.contains { line in line.roles.isEmpty } ? Roles.unassigned(language) : nil
        )
    }
}
