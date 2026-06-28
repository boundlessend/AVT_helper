import Foundation

enum TextTools {
    static func cleanRoleName(_ input: String) -> String {
        let trimmed: String = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Roles.unassigned
        }

        let replaced: String = trimmed
            .replacingOccurrences(of: " , ", with: "_")
            .replacingOccurrences(of: " / ", with: "_")
            .replacingOccurrences(of: " \\ ", with: "_")
            .replacingOccurrences(of: ",", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return replaced.isEmpty ? Roles.unassigned : replaced
    }

    static func cleanAssText(_ input: String) -> String {
        let withoutOverrides: String = input.replacingOccurrences(
            of: #"\{.*?\}"#,
            with: "",
            options: [.regularExpression]
        )
        return withoutOverrides
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\h", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func escapeAssText(_ input: String) -> String {
        input
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
            return cleanRoleName(String(input[groupRange]))
        }
        return extracted.reduce(into: [String]()) { result, role in
            let exists: Bool = result.contains { current in
                current.caseInsensitiveCompare(role) == .orderedSame
            }
            if !role.isEmpty && !exists {
                result.append(role)
            }
        }
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
            .reduce(into: [String]()) { result, role in
                let exists: Bool = result.contains { current in
                    current.caseInsensitiveCompare(role) == .orderedSame
                }
                if !exists {
                    result.append(role)
                }
            }
            .map { role in "[\(role)]" }
            .joined()
    }

    static func safeFileName(_ input: String) -> String {
        let invalid: CharacterSet = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let clean: String = input
            .components(separatedBy: invalid)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "export" : clean
    }

    static func xmlEscape(_ input: String) -> String {
        input
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
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
