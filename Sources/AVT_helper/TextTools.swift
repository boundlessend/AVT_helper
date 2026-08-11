import Foundation

enum TextTools {
    /// нормализует имя роли; пустая строка на выходе означает, что имени фактически нет
    static func cleanRoleName(_ input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " , ", with: "_")
            .replacingOccurrences(of: " / ", with: "_")
            .replacingOccurrences(of: " \\ ", with: "_")
            .replacingOccurrences(of: ",", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

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

    /// снимает разметку ASS: вырезает неэкранированные блоки {...}, разворачивает переносы и экранированные скобки
    static func cleanAssText(_ input: String) -> String {
        let withoutOverrides: String = input.replacingOccurrences(
            of: #"(?<!\\)\{.*?(?<!\\)\}"#,
            with: "",
            options: [.regularExpression]
        )
        return
            withoutOverrides
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\h", with: " ")
            .replacingOccurrences(of: "\\{", with: "{")
            .replacingOccurrences(of: "\\}", with: "}")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// готовит текст реплики к записи в ASS: переносы строк и фигурные скобки, иначе текст будет прочитан как разметка
    static func escapeAssText(_ input: String) -> String {
        input
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
            .replacingOccurrences(of: "\r\n", with: "\\N")
            .replacingOccurrences(of: "\n", with: "\\N")
            .replacingOccurrences(of: "\r", with: "\\N")
    }

    static func extractBracketRoles(_ input: String) -> [String] {
        guard let regex: NSRegularExpression = try? NSRegularExpression(pattern: #"\[(.*?)\]"#) else {
            return []
        }

        let range: NSRange = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches: [NSTextCheckingResult] = regex.matches(in: input, range: range)
        let extracted: [String] = matches.compactMap { match in
            guard let groupRange: Range<String.Index> = Range(match.range(at: 1), in: input) else {
                return nil
            }
            return String(input[groupRange])
        }
        return normalizedRoles(extracted)
    }

    static func removeLeadingBracketRoles(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { line in
                line.replacingOccurrences(
                    of: #"^\s*(\[[^\]]+\]\s*)+"#,
                    with: "",
                    options: [.regularExpression]
                )
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func squareRolePrefix(_ roles: [String]) -> String {
        roles
            .filter { role in !role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { role in "[\(role)]" }
            .joined()
    }

    static func safeFileName(_ input: String) -> String {
        let invalid: CharacterSet = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let clean: String =
            input
            .components(separatedBy: invalid)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "export" : clean
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

    static func normalizeSex(_ input: String) -> String {
        let value: String = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if ["М", "M", "МУЖ"].contains(value) {
            return "МУЖ"
        }
        if ["Ж", "ЖЕН", "F"].contains(value) {
            return "ЖЕН"
        }
        return "ОБЩ"
    }
}
