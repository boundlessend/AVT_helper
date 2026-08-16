import Foundation

enum SubtitleImporter {
    /// импортирует поддерживаемый файл субтитров и нормализует реплики по времени
    static func importFile(path: String, language: AppLanguage, progress: @escaping ProgressHandler = { _ in }) throws -> ImportedSubtitle {
        let url: URL = URL(fileURLWithPath: path)
        let sourceType: SubtitleSourceType = try detect(path: path)
        try validateFile(url: url, language: language)
        let text: String = try readText(url: url, language: language)
        let lines: [SubtitleLine]
        var script: AssScript?

        switch sourceType {
        case .ass, .ssa:
            let document: AssDocument = try importAss(text: text, progress: progress)
            lines = document.lines
            script = document.script
        case .srt:
            lines = try importSrt(text: text, progress: progress)
        case .vtt:
            lines = try importVtt(text: text, progress: progress)
        case .srp:
            lines = try importSrp(text: text, language: language, progress: progress)
        }

        if lines.isEmpty {
            throw SubtitleError.importFailed(L.text("error.noLines", language))
        }

        return ImportedSubtitle(
            baseName: url.deletingPathExtension().lastPathComponent,
            sourcePath: url.standardizedFileURL.path,
            sourceType: sourceType,
            lines: canonicalizedRoles(lines).sorted { left, right in
                if left.start == right.start {
                    return left.end < right.end
                }
                return left.start < right.start
            },
            assScript: script
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

    private static func validateFile(url: URL, language: AppLanguage) throws {
        let values: URLResourceValues = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        if values.isRegularFile != true {
            throw SubtitleError.importFailed(L.format("error.notRegularFile", language, ["path": url.path]))
        }
        let fileSize: UInt64 = UInt64(values.fileSize ?? 0)
        if fileSize > AppLimits.maxSubtitleFileBytes {
            throw SubtitleError.importFailed(
                L.format(
                    "error.fileTooLarge", language,
                    [
                        "size": L.fileSize(fileSize),
                        "max": L.fileSize(AppLimits.maxSubtitleFileBytes),
                    ]))
        }
    }

    /// читает файл, подбирая кодировку: BOM, затем UTF-8, UTF-16 без BOM, Windows-1251 и Latin-1.
    /// «декодировалось» само по себе ничего не значит: UTF-16 без BOM проходит проверку UTF-8,
    /// потому что нулевой байт - допустимый символ, и на выходе получается текст в дырках.
    /// поэтому каждый кандидат ещё и осматривается
    private static func readText(url: URL, language: AppLanguage) throws -> String {
        let data: Data = try Data(contentsOf: url)
        if let bomDecoded: String = decodeByBom(data: data) {
            return bomDecoded
        }
        if let wide: String = decodeUtf16WithoutBom(data: data) {
            return wide
        }
        let candidates: [String.Encoding] = [.utf8, windowsCyrillic, .isoLatin1]
        for encoding in candidates {
            if let text: String = String(data: data, encoding: encoding), isPlausibleText(text) {
                return text
            }
        }
        throw SubtitleError.importFailed(L.text("error.decodeFailed", language))
    }

    /// UTF-16 без BOM опознаётся по нулевым байтам, а не попыткой раскодировать:
    /// раскодировать удаётся любые чётные данные, и однобайтовый текст молча стал бы иероглифами.
    /// в субтитрах достаточно ASCII (цифры таймкода, двоеточия, стрелки), чтобы нули были заметны
    private static func decodeUtf16WithoutBom(data: Data) -> String? {
        guard data.count >= 4, data.count.isMultiple(of: 2) else {
            return nil
        }
        let sample: Data = data.prefix(4096)
        var evenZeros: Int = 0
        var oddZeros: Int = 0
        for (index, byte) in sample.enumerated() where byte == 0 {
            if index.isMultiple(of: 2) {
                evenZeros += 1
            } else {
                oddZeros += 1
            }
        }
        let threshold: Int = sample.count / 8
        if oddZeros > threshold, evenZeros * 4 <= oddZeros {
            return String(data: data, encoding: .utf16LittleEndian)
        }
        if evenZeros > threshold, oddZeros * 4 <= evenZeros {
            return String(data: data, encoding: .utf16BigEndian)
        }
        return nil
    }

    /// текст субтитров состоит из печатных символов и переводов строки. управляющие символы
    /// и знаки замены означают, что кодировку подобрали неверно, а не что файл такой
    private static func isPlausibleText(_ text: String) -> Bool {
        var total: Int = 0
        var broken: Int = 0
        for scalar in text.unicodeScalars {
            total += 1
            switch scalar.value {
            case 0x09, 0x0A, 0x0D:
                continue
            case 0..<0x20, 0x7F..<0xA0, 0xFFFD:
                broken += 1
            default:
                continue
            }
        }
        if total == 0 {
            return false
        }
        return Double(broken) / Double(total) < 0.01
    }

    private static func decodeByBom(data: Data) -> String? {
        let bytes: [UInt8] = [UInt8](data.prefix(3))
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if bytes.count >= 2, (bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF) {
            return String(data: data, encoding: .utf16)
        }
        return nil
    }

    private static let windowsCyrillic: String.Encoding = {
        let raw: UInt = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsCyrillic.rawValue))
        return String.Encoding(rawValue: raw)
    }()

    /// реплики файла вместе с его заголовком: заголовок нужен экспорту, чтобы стили не осиротели
    private struct AssDocument {
        let lines: [SubtitleLine]
        let script: AssScript?
    }

    /// порядок полей строки Dialogue по умолчанию. формат разрешает свой порядок,
    /// и он объявлен строкой Format внутри [Events]
    private static let defaultAssFields: [String] = [
        "layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text",
    ]

    private static func importAss(text: String, progress: @escaping ProgressHandler) throws -> AssDocument {
        let rawLines: [String] = text.components(separatedBy: .newlines)
        var counter: ProgressCounter = ProgressCounter(total: rawLines.count, report: progress)

        var section: String = ""
        var scriptInfo: [String] = []
        var styles: [String] = []
        var stylesSection: String = ""
        var fields: [String] = defaultAssFields
        var lines: [SubtitleLine] = []

        for rawLine in rawLines {
            try counter.step()
            let trimmed: String = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                section = trimmed.lowercased()
                if section.contains("styles") {
                    stylesSection = trimmed
                }
                continue
            }

            switch section {
            case "[script info]":
                scriptInfo.append(trimmed)
            case let name where name.contains("styles"):
                styles.append(trimmed)
            case "[events]":
                if let declared: [String] = assFieldOrder(trimmed) {
                    fields = declared
                    continue
                }
                if let line: SubtitleLine = parseAssDialogue(trimmed, fields: fields) {
                    lines.append(line)
                }
            default:
                continue
            }
        }

        let script: AssScript? =
            styles.isEmpty
            ? nil
            : AssScript(
                scriptInfo: scriptInfo,
                styles: styles,
                stylesSection: stylesSection
            )
        return AssDocument(lines: lines, script: script)
    }

    /// читает строку Format блока [Events]; nil означает, что это не она
    private static func assFieldOrder(_ line: String) -> [String]? {
        guard line.range(of: "Format:", options: [.caseInsensitive, .anchored]) != nil else {
            return nil
        }
        let declared: [String] =
            line
            .dropFirst("Format:".count)
            .components(separatedBy: ",")
            .map { field in field.trimmingCharacters(in: .whitespaces).lowercased() }
        // текст обязан идти последним: только он имеет право содержать запятые
        guard declared.count >= 4, declared.last == "text" else {
            return nil
        }
        return declared
    }

    private static func parseAssDialogue(_ line: String, fields: [String]) -> SubtitleLine? {
        guard line.range(of: "Dialogue:", options: [.caseInsensitive, .anchored]) != nil else {
            return nil
        }
        let payload: String = String(line.dropFirst("Dialogue:".count))
        let parts: [Substring] = payload.split(
            separator: ",",
            maxSplits: fields.count - 1,
            omittingEmptySubsequences: false
        )
        guard parts.count == fields.count else {
            return nil
        }

        let value: (String) -> String = { name in
            guard let index: Int = fields.firstIndex(of: name) else {
                return ""
            }
            return String(parts[index]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start: TimeInterval = try? TimeTools.parseAss(value("start")),
            let end: TimeInterval = try? TimeTools.parseAss(value("end"))
        else {
            return nil
        }

        let style: String = value("style")
        let effect: String = value("effect")
        let role: String = inferAssRole(name: value("name"), style: style, effect: effect)
        return SubtitleLine(
            id: UUID(),
            start: start,
            end: end,
            roles: TextTools.normalizedRoles(role.components(separatedBy: TextTools.assRoleSeparator)),
            text: TextTools.cleanAssText(value("text")),
            style: style,
            effect: effect,
            sex: .unknown
        )
    }

    private static func importSrt(text: String, progress: @escaping ProgressHandler) throws -> [SubtitleLine] {
        let blocks: [String] = normalizedBlocks(text: text)
        var counter: ProgressCounter = ProgressCounter(total: blocks.count, report: progress)
        return try blocks.compactMap { block in
            try counter.step()
            let lines: [String] = block.components(separatedBy: "\n")
            guard let timeIndex: Int = lines.firstIndex(where: { line in line.contains("-->") }) else {
                return nil
            }
            let timeParts: [String] = lines[timeIndex].components(separatedBy: "-->")
            guard timeParts.count == 2,
                let start: TimeInterval = try? TimeTools.parseSrt(timeParts[0]),
                let end: TimeInterval = try? TimeTools.parseSrt(timeParts[1])
            else {
                return nil
            }
            let rawText: String = lines.dropFirst(timeIndex + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return buildLine(start: start, end: end, rawText: rawText)
        }
    }

    private static func importVtt(text: String, progress: @escaping ProgressHandler) throws -> [SubtitleLine] {
        let withoutHeader: String = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        let blocks: [String] = normalizedBlocks(text: withoutHeader)
        var counter: ProgressCounter = ProgressCounter(total: blocks.count, report: progress)
        return try blocks.compactMap { block in
            try counter.step()
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
                )
            else {
                return nil
            }
            let rawText: String = lines.dropFirst(timeIndex + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return buildVttLine(start: start, end: end, rawText: rawText)
        }
    }

    private static func importSrp(text: String, language: AppLanguage, progress: @escaping ProgressHandler) throws -> [SubtitleLine] {
        let data: Data = Data(text.utf8)
        // внешние сущности выключены: иначе чужой SRP прочитает локальный файл или сходит в сеть при импорте
        let document: XMLDocument = try XMLDocument(data: data, options: [.nodePreserveWhitespace, .nodeLoadExternalEntitiesNever])
        // DTD в субтитрах не нужен ни одному инструменту, зато через него разворачивают сущности-бомбы
        if document.dtd != nil {
            throw SubtitleError.importFailed(L.text("error.xmlEntities", language))
        }
        let nodes: [XMLNode] = try document.nodes(forXPath: "//DocumentElement")
        var counter: ProgressCounter = ProgressCounter(total: nodes.count, report: progress)
        return try nodes.compactMap { node in
            try counter.step()
            let roles: [String] = TextTools.normalizedRoles([childText(node: node, name: "Character")])
            let sex: SourceSex = SourceSex.parse(childText(node: node, name: "Sex"))
            let rawText: String = childText(node: node, name: "Text")
                .replacingOccurrences(of: "\\N", with: " ")
                .replacingOccurrences(of: "\\n", with: " ")
                .replacingOccurrences(of: "\\h", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let start: TimeInterval = flexibleTime(childText(node: node, name: "BeginTime")),
                let end: TimeInterval = flexibleTime(childText(node: node, name: "EndTime"))
            else {
                return nil
            }
            return SubtitleLine(id: UUID(), start: start, end: end, roles: roles, text: rawText, style: "", effect: "", sex: sex)
        }
    }

    /// сводит написания одной роли к первому встреченному: иначе «Анна» и «АННА» живут как две роли
    /// с раздельными счётчиками, цветами и файлами
    private static func canonicalizedRoles(_ lines: [SubtitleLine]) -> [SubtitleLine] {
        var canonical: [String: String] = [:]
        for line in lines {
            for role in line.roles where canonical[role.lowercased()] == nil {
                canonical[role.lowercased()] = role
            }
        }
        return lines.map { line in
            SubtitleLine(
                id: line.id,
                start: line.start,
                end: line.end,
                roles: TextTools.normalizedRoles(line.roles.map { role in canonical[role.lowercased()] ?? role }),
                text: line.text,
                style: line.style,
                effect: line.effect,
                sex: line.sex
            )
        }
    }

    /// в WebVTT роль размечают тегом <v Имя>, но встречаются и квадратные скобки: принимаются оба способа
    private static func buildVttLine(start: TimeInterval, end: TimeInterval, rawText: String) -> SubtitleLine {
        let voiceRoles: [String] = TextTools.extractVoiceTagRoles(rawText)
        let cleanText: String = TextTools.cleanVttText(rawText)
        if voiceRoles.isEmpty {
            return buildLine(start: start, end: end, rawText: cleanText)
        }
        return SubtitleLine(id: UUID(), start: start, end: end, roles: voiceRoles, text: cleanText, style: "", effect: "", sex: .unknown)
    }

    private static func buildLine(start: TimeInterval, end: TimeInterval, rawText: String) -> SubtitleLine {
        let roles: [String] = TextTools.extractBracketRoles(rawText)
        let cleanText: String = {
            let cleaned: String = TextTools.removeLeadingBracketRoles(rawText)
            return cleaned.isEmpty ? rawText : cleaned
        }()
        return SubtitleLine(id: UUID(), start: start, end: end, roles: roles, text: cleanText, style: "", effect: "", sex: .unknown)
    }

    private static func normalizedBlocks(text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")
            .map { block in block.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { block in !block.isEmpty }
    }

    /// выбирает имя роли из полей строки Dialogue; пустая строка означает, что роль не распознана
    private static func inferAssRole(name: String, style: String, effect: String) -> String {
        if !name.isEmpty && !Roles.isOwnPlaceholder(name) {
            return name
        }
        if !style.isEmpty && style.caseInsensitiveCompare("Default") != .orderedSame {
            return style
        }
        return effect
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
