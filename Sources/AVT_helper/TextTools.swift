import Foundation

enum TextTools {
    /// нормализует имя роли; пустая строка на выходе означает, что имени фактически нет
    static func cleanRoleName(_ input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " , ", with: "_")
            .replacingOccurrences(of: " / ", with: "_")
            .replacingOccurrences(of: " \\ ", with: "_")
            .replacingOccurrences(of: " \(assRoleSeparator) ", with: "_")
            .replacingOccurrences(of: ",", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: assRoleSeparator, with: "_")
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// в ASS поле Name одно, а реплику могут произносить хором: роли пишутся через этот разделитель
    /// и по нему же читаются обратно, поэтому cleanRoleName вычищает его из самих имён
    static let assRoleSeparator: String = "|"

    /// приводит список сырых имён к очищенным уникальным ролям без учёта регистра
    static func normalizedRoles(_ input: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for name in input {
            let role: String = cleanRoleName(name)
            if !role.isEmpty && seen.insert(role.lowercased()).inserted {
                result.append(role)
            }
        }
        return result
    }

    /// снимает разметку ASS: вырезает неэкранированные блоки {...}, разворачивает переносы и экранированные символы
    static func cleanAssText(_ input: String) -> String {
        let withoutOverrides: String = removingMatches(assOverrideRegex, in: input)
        return unescapeAssText(withoutOverrides).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// готовит текст реплики к записи в ASS: обратный слэш, фигурные скобки и переносы строк,
    /// иначе текст будет прочитан как разметка. пустой блок {} после экранированной скобки нужен VSFilter:
    /// он не понимает \{ и без него съедает текст до следующей закрывающей скобки
    static func escapeAssText(_ input: String) -> String {
        var result: String = ""
        result.reserveCapacity(input.count)
        for character in input.replacingOccurrences(of: "\r\n", with: "\n") {
            switch character {
            case "\\":
                result += "\\\\"
            case "{":
                result += "\\{{}"
            case "}":
                result += "\\}{}"
            case "\n", "\r":
                result += "\\N"
            default:
                result.append(character)
            }
        }
        return result
    }

    /// разворачивает экранирование ASS одним проходом слева направо: цепочка замен прочитала бы
    /// "\\n" из экранированного обратного слэша как перенос строки
    private static func unescapeAssText(_ input: String) -> String {
        let characters: [Character] = Array(input)
        var result: String = ""
        result.reserveCapacity(characters.count)
        var index: Int = 0
        while index < characters.count {
            let character: Character = characters[index]
            guard character == "\\", index + 1 < characters.count else {
                result.append(character)
                index += 1
                continue
            }
            let next: Character = characters[index + 1]
            switch next {
            case "N", "n":
                result.append("\n")
            case "h":
                result.append(" ")
            case "\\", "{", "}":
                result.append(next)
            default:
                result.append(character)
                result.append(next)
            }
            index += 2
        }
        return result
    }

    /// пометки роли стоят в начале строки; те же скобки посреди реплики - это ремарка, а не имя
    private static let leadingRolesPattern: String = #"^\s*(\[[^\]]+\]\s*)+"#

    /// шаблоны компилируются один раз на тип, а не на каждую реплику
    private static let bracketRoleRegex: NSRegularExpression? = try? NSRegularExpression(pattern: #"\[([^\]]*)\]"#)
    private static let voiceTagRegex: NSRegularExpression? = try? NSRegularExpression(pattern: #"^\s*<v(?:\.[^\s>]+)*\s+([^>]+)>"#)
    private static let assOverrideRegex: NSRegularExpression? = try? NSRegularExpression(pattern: #"(?<!\\)\{.*?(?<!\\)\}"#)
    private static let vttTagRegex: NSRegularExpression? = try? NSRegularExpression(pattern: #"</?[^>]+>"#)

    private static func removingMatches(_ regex: NSRegularExpression?, in input: String) -> String {
        guard let regex: NSRegularExpression = regex else {
            return input
        }
        let range: NSRange = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: "")
    }

    static func extractBracketRoles(_ input: String) -> [String] {
        guard let regex: NSRegularExpression = bracketRoleRegex else {
            return []
        }

        let extracted: [String] = normalizedLines(input).flatMap { line -> [String] in
            guard let prefixRange: Range<String.Index> = line.range(of: leadingRolesPattern, options: [.regularExpression]) else {
                return []
            }
            let prefix: String = String(line[prefixRange])
            let range: NSRange = NSRange(prefix.startIndex..<prefix.endIndex, in: prefix)
            return regex.matches(in: prefix, range: range).compactMap { match in
                guard let groupRange: Range<String.Index> = Range(match.range(at: 1), in: prefix) else {
                    return nil
                }
                return String(prefix[groupRange])
            }
        }
        return normalizedRoles(extracted)
    }

    static func removeLeadingBracketRoles(_ input: String) -> String {
        normalizedLines(input)
            .map { line in
                line.replacingOccurrences(of: leadingRolesPattern, with: "", options: [.regularExpression])
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// имена говорящих из тегов <v Имя> в начале строк WebVTT: штатная разметка роли этого формата
    static func extractVoiceTagRoles(_ input: String) -> [String] {
        guard let regex: NSRegularExpression = voiceTagRegex else {
            return []
        }
        let names: [String] = normalizedLines(input).compactMap { line in
            let range: NSRange = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match: NSTextCheckingResult = regex.firstMatch(in: line, range: range),
                let groupRange: Range<String.Index> = Range(match.range(at: 1), in: line)
            else {
                return nil
            }
            return String(line[groupRange])
        }
        return normalizedRoles(names)
    }

    /// снимает разметку WebVTT и разворачивает её сущности: в реплике должен остаться только текст
    static func cleanVttText(_ input: String) -> String {
        let withoutTags: String = removingMatches(vttTagRegex, in: input)
        return
            withoutTags
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedLines(_ input: String) -> [String] {
        input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
    }

    static func squareRolePrefix(_ roles: [String]) -> String {
        roles
            .filter { role in !role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { role in "[\(role)]" }
            .joined()
    }

    /// имя файла без запрещённых и управляющих символов, без ведущих точек и не длиннее предела файловой системы:
    /// длинная роль в имени иначе роняет запись посреди прогона, а точка в начале прячет файл
    static func safeFileName(_ input: String) -> String {
        let invalid: CharacterSet = CharacterSet(charactersIn: "/\\?%*|\"<>:").union(.controlCharacters)
        let sanitized: String =
            input
            .components(separatedBy: invalid)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clean: String = String(sanitized.drop(while: { character in character == "." }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "export" : truncated(clean, toBytes: AppLimits.maxFileNameBytes)
    }

    /// обрезает строку по границе символа так, чтобы её длина в UTF-8 уложилась в предел
    private static func truncated(_ input: String, toBytes limit: Int) -> String {
        if input.utf8.count <= limit {
            return input
        }
        var result: String = ""
        var used: Int = 0
        for character in input {
            let size: Int = String(character).utf8.count
            if used + size > limit {
                break
            }
            result.append(character)
            used += size
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// экранирует спецсимволы и выбрасывает символы, недопустимые в XML 1.0: иначе Word отказывается открывать docx
    static func xmlEscape(_ input: String) -> String {
        var result: String = ""
        result.reserveCapacity(input.unicodeScalars.count)
        for scalar in input.unicodeScalars {
            switch scalar {
            case "&":
                result += "&amp;"
            case "<":
                result += "&lt;"
            case ">":
                result += "&gt;"
            case "\"":
                result += "&quot;"
            case "'":
                result += "&apos;"
            default:
                if isAllowedInXml(scalar) {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }

    private static func isAllowedInXml(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A, 0x0D, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF:
            return true
        default:
            return false
        }
    }
}
