import Foundation

enum SubtitleImporter {
    /// импортирует поддерживаемый файл субтитров и нормализует реплики по времени
    static func importFile(path: String) throws -> ImportedSubtitle {
        let url: URL = URL(fileURLWithPath: path)
        let sourceType: SubtitleSourceType = try detect(path: path)
        try validateFile(url: url)
        let text: String = try String(contentsOf: url, encoding: .utf8)
        let lines: [SubtitleLine]

        switch sourceType {
        case .ass, .ssa:
            lines = try importAss(text: text)
        case .srt:
            lines = try importSrt(text: text)
        case .vtt:
            lines = try importVtt(text: text)
        case .srp:
            lines = try importSrp(text: text)
        }

        return ImportedSubtitle(
            baseName: url.deletingPathExtension().lastPathComponent,
            sourceType: sourceType,
            lines: lines.sorted { left, right in
                if left.start == right.start {
                    return left.end < right.end
                }
                return left.start < right.start
            }
        )
    }

    static func detect(path: String) throws -> SubtitleSourceType {
        let ext: String = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "ass":
            return .ass
        case "ssa":
            return .ssa
        case "srt":
            return .srt
        case "vtt":
            return .vtt
        case "srp":
            return .srp
        default:
            throw SubtitleError.unsupportedFormat(path)
        }
    }

    private static func validateFile(url: URL) throws {
        let values: URLResourceValues = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        let language: AppLanguage = AppLanguage.current
        if values.isRegularFile != true {
            throw SubtitleError.importFailed(L.format("error.notRegularFile", language, ["path": url.path]))
        }
        let fileSize: UInt64 = UInt64(values.fileSize ?? 0)
        if fileSize > AppLimits.maxSubtitleFileBytes {
            throw SubtitleError.importFailed(L.format("error.fileTooLarge", language, [
                "size": String(fileSize),
                "max": String(AppLimits.maxSubtitleFileBytes)
            ]))
        }
    }

    private static func importAss(text: String) throws -> [SubtitleLine] {
        text.components(separatedBy: .newlines).compactMap { rawLine in
            guard rawLine.range(of: "Dialogue:", options: [.caseInsensitive, .anchored]) != nil else {
                return nil
            }
            let payload: String = String(rawLine.dropFirst("Dialogue:".count))
            let parts: [Substring] = payload.split(separator: ",", maxSplits: 9, omittingEmptySubsequences: false)
            guard parts.count >= 10,
                  let start: TimeInterval = try? TimeTools.parseAss(String(parts[1])),
                  let end: TimeInterval = try? TimeTools.parseAss(String(parts[2])) else {
                return nil
            }

            let style: String = String(parts[3]).trimmingCharacters(in: .whitespacesAndNewlines)
            let name: String = String(parts[4]).trimmingCharacters(in: .whitespacesAndNewlines)
            let effect: String = String(parts[8]).trimmingCharacters(in: .whitespacesAndNewlines)
            let role: String = inferAssRole(name: name, style: style, effect: effect)
            let cleanRole: String = TextTools.cleanRoleName(role)
            return SubtitleLine(
                id: UUID(),
                start: start,
                end: end,
                role: cleanRole,
                roles: [cleanRole],
                text: TextTools.cleanAssText(String(parts[9])),
                style: style,
                effect: effect,
                sex: ""
            )
        }
    }

    private static func importSrt(text: String) throws -> [SubtitleLine] {
        let blocks: [String] = normalizedBlocks(text: text)
        return blocks.compactMap { block in
            let lines: [String] = block.components(separatedBy: "\n")
            guard let timeIndex: Int = lines.firstIndex(where: { line in line.contains("-->") }) else {
                return nil
            }
            let timeParts: [String] = lines[timeIndex].components(separatedBy: "-->")
            guard timeParts.count == 2,
                  let start: TimeInterval = try? TimeTools.parseSrt(timeParts[0]),
                  let end: TimeInterval = try? TimeTools.parseSrt(timeParts[1]) else {
                return nil
            }
            let rawText: String = lines.dropFirst(timeIndex + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return buildLine(start: start, end: end, rawText: rawText)
        }
    }

    private static func importVtt(text: String) throws -> [SubtitleLine] {
        let withoutHeader: String = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        let blocks: [String] = normalizedBlocks(text: withoutHeader)
        return blocks.compactMap { block in
            if block.uppercased().hasPrefix("WEBVTT") || block.uppercased().hasPrefix("NOTE") {
                return nil
            }
            let lines: [String] = block.components(separatedBy: "\n")
            guard let timeIndex: Int = lines.firstIndex(where: { line in line.contains("-->") }) else {
                return nil
            }
            let timeParts: [String] = lines[timeIndex].components(separatedBy: "-->")
            guard timeParts.count == 2,
                  let start: TimeInterval = try? TimeTools.parseVtt(timeParts[0]),
                  let end: TimeInterval = try? TimeTools.parseVtt(
                    timeParts[1]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .components(separatedBy: .whitespaces)
                        .first ?? ""
                  ) else {
                return nil
            }
            let rawText: String = lines.dropFirst(timeIndex + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return buildLine(start: start, end: end, rawText: rawText)
        }
    }

    private static func importSrp(text: String) throws -> [SubtitleLine] {
        let data: Data = Data(text.utf8)
        let document: XMLDocument = try XMLDocument(data: data, options: [.nodePreserveWhitespace])
        let nodes: [XMLNode] = try document.nodes(forXPath: "//DocumentElement")
        return nodes.compactMap { node in
            let role: String = TextTools.cleanRoleName(childText(node: node, name: "Character"))
            let sex: String = TextTools.normalizeSex(childText(node: node, name: "Sex"))
            let rawText: String = childText(node: node, name: "Text")
                .replacingOccurrences(of: "\\N", with: " ")
                .replacingOccurrences(of: "\\n", with: " ")
                .replacingOccurrences(of: "\\h", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let start: TimeInterval = flexibleTime(childText(node: node, name: "BeginTime")),
                  let end: TimeInterval = flexibleTime(childText(node: node, name: "EndTime")) else {
                return nil
            }
            return SubtitleLine(id: UUID(), start: start, end: end, role: role, roles: [role], text: rawText, style: "", effect: "", sex: sex)
        }
    }

    private static func buildLine(start: TimeInterval, end: TimeInterval, rawText: String) -> SubtitleLine {
        let roles: [String] = TextTools.extractBracketRoles(rawText)
        let cleanText: String = {
            let cleaned: String = TextTools.removeLeadingBracketRoles(rawText)
            return cleaned.isEmpty ? rawText : cleaned
        }()
        let role: String = roles.first ?? Roles.unassigned
        return SubtitleLine(id: UUID(), start: start, end: end, role: role, roles: roles.isEmpty ? [role] : roles, text: cleanText, style: "", effect: "", sex: "")
    }

    private static func normalizedBlocks(text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")
            .map { block in block.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { block in !block.isEmpty }
    }

    private static func inferAssRole(name: String, style: String, effect: String) -> String {
        if !name.isEmpty && name.caseInsensitiveCompare(Roles.unassigned) != .orderedSame {
            return name
        }
        if !style.isEmpty && style.caseInsensitiveCompare("Default") != .orderedSame {
            return style
        }
        if !effect.isEmpty {
            return effect
        }
        return Roles.unassigned
    }

    private static func childText(node: XMLNode, name: String) -> String {
        let nodes: [XMLNode] = (try? node.nodes(forXPath: name)) ?? []
        return nodes.first?.stringValue ?? ""
    }

    private static func flexibleTime(_ input: String) -> TimeInterval? {
        if let value: TimeInterval = try? TimeTools.parseSrt(input.replacingOccurrences(of: ".", with: ",")) {
            return value
        }
        if let value: TimeInterval = try? TimeTools.parseAss(input.replacingOccurrences(of: ",", with: ".")) {
            return value
        }
        return nil
    }
}
