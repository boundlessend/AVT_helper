import Foundation

enum SubtitleImporter {
    /// импортирует поддерживаемый файл субтитров и нормализует реплики по времени
    static func importFile(path: String, language: AppLanguage, progress: @escaping ProgressHandler = { _ in }) throws -> ImportedSubtitle {
        let url: URL = URL(fileURLWithPath: path)
        let sourceType: SubtitleSourceType = try detect(path: path)
        try validateFile(url: url, language: language)
        let text: String = try readText(url: url, language: language)
        let parsed: ParsedLines
        var script: AssScript?

        switch sourceType {
        case .ass, .ssa:
            let document: AssDocument = try importAss(text: text, language: language, progress: progress)
            parsed = document.parsed
            script = document.script
        case .srt:
            parsed = try importSrt(text: text, progress: progress)
        case .vtt:
            parsed = try importVtt(text: text, progress: progress)
        case .srp:
            parsed = try importSrp(text: text, language: language, progress: progress)
        }

        if parsed.lines.isEmpty {
            throw SubtitleError.importFailed(L.text("error.noLines", language))
        }

        return ImportedSubtitle(
            baseName: url.deletingPathExtension().lastPathComponent,
            sourcePath: url.standardizedFileURL.path,
            sourceType: sourceType,
            lines: orderedByTime(canonicalizedRoles(parsed.lines)),
            assScript: script,
            skippedBlocks: parsed.skipped
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
                        "size": L.fileSize(fileSize, language),
                        "max": L.fileSize(AppLimits.maxSubtitleFileBytes, language),
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
        // пустой текст раскодирован верно: про отсутствие реплик пользователю скажет error.noLines
        if total == 0 {
            return true
        }
        return Double(broken) / Double(total) < 0.01
    }

    private static func decodeByBom(data: Data) -> String? {
        let bytes: [UInt8] = [UInt8](data.prefix(4))
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            return plausibleOrNil(String(data: data.dropFirst(3), encoding: .utf8))
        }
        // UTF-32 проверяется раньше UTF-16: её BOM начинается той же парой байтов, и файл прочитался бы в нули
        if bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xFE, bytes[2] == 0x00, bytes[3] == 0x00 {
            return plausibleOrNil(String(data: data, encoding: .utf32))
        }
        if bytes.count >= 4, bytes[0] == 0x00, bytes[1] == 0x00, bytes[2] == 0xFE, bytes[3] == 0xFF {
            return plausibleOrNil(String(data: data, encoding: .utf32))
        }
        if bytes.count >= 2, (bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF) {
            return plausibleOrNil(String(data: data, encoding: .utf16))
        }
        return nil
    }

    /// BOM говорит только о разметке байтов: текст всё равно осматривается, иначе подмена BOM даёт мусор
    private static func plausibleOrNil(_ text: String?) -> String? {
        guard let text: String = text, isPlausibleText(text) else {
            return nil
        }
        return text
    }

    private static let windowsCyrillic: String.Encoding = {
        let raw: UInt = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsCyrillic.rawValue))
        return String.Encoding(rawValue: raw)
    }()

    /// разобранные реплики вместе с числом блоков, которые разобрать не удалось:
    /// молчаливая потеря части файла выглядит для пользователя как файл, где этих реплик и не было
    struct ParsedLines {
        let lines: [SubtitleLine]
        let skipped: Int
    }

    /// реплики файла вместе с его заголовком: заголовок нужен экспорту, чтобы стили не осиротели
    private struct AssDocument {
        let parsed: ParsedLines
        let script: AssScript?
    }

    /// порядок полей строки Dialogue по умолчанию. формат разрешает свой порядок,
    /// и он объявлен строкой Format внутри [Events]
    private static let defaultAssFields: [String] = [
        "layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text",
    ]

    private static func importAss(text: String, language: AppLanguage, progress: @escaping ProgressHandler) throws -> AssDocument {
        let rawLines: [String] = normalizedNewlines(text).components(separatedBy: "\n")
        var counter: ProgressCounter = ProgressCounter(total: rawLines.count, report: progress)

        var section: String = ""
        var scriptInfo: [String] = []
        var styles: [String] = []
        var stylesSection: String = ""
        var fields: [String] = defaultAssFields
        var lines: [SubtitleLine] = []
        var skipped: Int = 0

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
                if isAssFormatLine(trimmed) {
                    guard let declared: [String] = assFieldOrder(trimmed) else {
                        throw SubtitleError.importFailed(L.text("error.assFieldOrder", language))
                    }
                    fields = declared
                    continue
                }
                if let line: SubtitleLine = parseAssDialogue(trimmed, fields: fields) {
                    lines.append(line)
                } else if trimmed.range(of: "Dialogue:", options: [.caseInsensitive, .anchored]) != nil {
                    skipped += 1
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
        return AssDocument(parsed: ParsedLines(lines: lines, skipped: skipped), script: script)
    }

    private static func isAssFormatLine(_ line: String) -> Bool {
        line.range(of: "Format:", options: [.caseInsensitive, .anchored]) != nil
    }

    /// читает порядок полей строки Format блока [Events]; nil означает, что порядок непригоден для разбора
    private static func assFieldOrder(_ line: String) -> [String]? {
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
        // конец раньше начала - такая же порча, как неразобранный таймкод: реплика отбрасывается
        guard let start: TimeInterval = try? TimeTools.parseAss(value("start")),
            let end: TimeInterval = try? TimeTools.parseAss(value("end")),
            end >= start
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
            sex: .unknown,
            layer: Int(value("layer")) ?? 0,
            marginL: Int(value("marginl")) ?? 0,
            marginR: Int(value("marginr")) ?? 0,
            marginV: Int(value("marginv")) ?? 0
        )
    }

    /// разобранный блок «номер, строка со стрелкой, текст»: он одинаков у SRT и VTT
    private struct TimedBlock {
        let start: TimeInterval
        let end: TimeInterval
        let rawText: String
    }

    /// разбирает блок по строке со стрелкой; endTime приводит правую часть к таймкоду, отрезая cue settings у VTT
    private static func parseTimedBlock(
        _ block: String,
        parseTime: (String) throws -> TimeInterval,
        endTime: (String) -> String
    ) -> TimedBlock? {
        let lines: [String] = block.components(separatedBy: "\n")
        guard let timeIndex: Int = lines.firstIndex(where: { line in line.contains("-->") }) else {
            return nil
        }
        let timeParts: [String] = lines[timeIndex].components(separatedBy: "-->")
        // конец раньше начала - такая же порча, как неразобранный таймкод: реплика отбрасывается
        guard timeParts.count == 2,
            let start: TimeInterval = try? parseTime(timeParts[0]),
            let end: TimeInterval = try? parseTime(endTime(timeParts[1])),
            end >= start
        else {
            return nil
        }
        let rawText: String = lines.dropFirst(timeIndex + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return TimedBlock(start: start, end: end, rawText: rawText)
    }

    private static func importSrt(text: String, progress: @escaping ProgressHandler) throws -> ParsedLines {
        let blocks: [String] = normalizedBlocks(text: text)
        var counter: ProgressCounter = ProgressCounter(total: blocks.count, report: progress)
        var lines: [SubtitleLine] = []
        var skipped: Int = 0
        for block in blocks {
            try counter.step()
            guard let parsed: TimedBlock = parseTimedBlock(block, parseTime: TimeTools.parseSrt, endTime: { part in part }) else {
                skipped += 1
                continue
            }
            lines.append(buildLine(start: parsed.start, end: parsed.end, rawText: parsed.rawText))
        }
        return ParsedLines(lines: lines, skipped: skipped)
    }

    private static func importVtt(text: String, progress: @escaping ProgressHandler) throws -> ParsedLines {
        let withoutHeader: String = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        let blocks: [String] = normalizedBlocks(text: withoutHeader)
        var counter: ProgressCounter = ProgressCounter(total: blocks.count, report: progress)
        var lines: [SubtitleLine] = []
        var skipped: Int = 0
        for block in blocks {
            try counter.step()
            // служебный блок это не потерянная реплика, поэтому в счёт пропусков он не идёт
            if isVttMetadataBlock(block) {
                continue
            }
            guard let parsed: TimedBlock = parseTimedBlock(block, parseTime: TimeTools.parseVtt, endTime: vttEndTime) else {
                skipped += 1
                continue
            }
            lines.append(buildVttLine(start: parsed.start, end: parsed.end, rawText: parsed.rawText))
        }
        return ParsedLines(lines: lines, skipped: skipped)
    }

    /// в VTT за конечным таймкодом идут cue settings, отделённые пробелом: времени принадлежит только первое слово
    private static func vttEndTime(_ part: String) -> String {
        part.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespaces).first ?? ""
    }

    private static let vttMetadataKeywords: [String] = ["WEBVTT", "NOTE", "STYLE", "REGION"]

    /// служебный блок опознаётся по первой строке целиком: идентификатор cue вида «NOTES-3» служебным не является
    private static func isVttMetadataBlock(_ block: String) -> Bool {
        let head: String = (block.components(separatedBy: "\n").first ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        return vttMetadataKeywords.contains { keyword in
            head == keyword || head.hasPrefix(keyword + " ") || head.hasPrefix(keyword + "\t")
        }
    }

    private static func importSrp(text: String, language: AppLanguage, progress: @escaping ProgressHandler) throws -> ParsedLines {
        // внутренние сущности разворачиваются уже в конструкторе XMLDocument, поэтому DOCTYPE ищется в тексте:
        // 581 байт бомбы иначе успевают развернуться в гигабайт до любой проверки
        if declaresDoctype(text) {
            throw SubtitleError.importFailed(L.text("error.xmlEntities", language))
        }
        let data: Data = Data(xmlWithUtf8Declaration(text).utf8)
        // внешние сущности выключены: иначе чужой SRP прочитает локальный файл или сходит в сеть при импорте
        let document: XMLDocument = try XMLDocument(data: data, options: [.nodePreserveWhitespace, .nodeLoadExternalEntitiesNever])
        // DTD в субтитрах не нужен ни одному инструменту, зато через него разворачивают сущности-бомбы
        if document.dtd != nil {
            throw SubtitleError.importFailed(L.text("error.xmlEntities", language))
        }
        let nodes: [XMLNode] = try document.nodes(forXPath: "//DocumentElement")
        var counter: ProgressCounter = ProgressCounter(total: nodes.count, report: progress)
        var lines: [SubtitleLine] = []
        var skipped: Int = 0
        for node in nodes {
            try counter.step()
            let roles: [String] = TextTools.normalizedRoles([childText(node: node, name: "Character")])
            let sex: SourceSex = SourceSex.parse(childText(node: node, name: "Sex"))
            let rawText: String = childText(node: node, name: "Text")
                .replacingOccurrences(of: "\\N", with: " ")
                .replacingOccurrences(of: "\\n", with: " ")
                .replacingOccurrences(of: "\\h", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // конец раньше начала - такая же порча, как неразобранный таймкод: реплика отбрасывается
            guard let start: TimeInterval = flexibleTime(childText(node: node, name: "BeginTime")),
                let end: TimeInterval = flexibleTime(childText(node: node, name: "EndTime")),
                end >= start
            else {
                skipped += 1
                continue
            }
            lines.append(SubtitleLine(id: UUID(), start: start, end: end, roles: roles, text: rawText, style: "", effect: "", sex: sex))
        }
        return ParsedLines(lines: lines, skipped: skipped)
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
            line.withRoles(TextTools.normalizedRoles(line.roles.map { role in canonical[role.lowercased()] ?? role }))
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
        normalizedNewlines(text)
            // пустая строка с пробелами или табуляцией тоже разделяет блоки, иначе две реплики склеиваются в одну
            .replacingOccurrences(of: "\n[ \t]*\n", with: "\n\n", options: .regularExpression)
            .components(separatedBy: "\n\n")
            .map { block in block.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { block in !block.isEmpty }
    }

    /// приводит переводы строк к \n: иначе CRLF даёт лишний пустой элемент при разбиении
    private static func normalizedNewlines(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// порядок реплик детерминирован: одинаковые таймкоды разводит исходный номер, иначе хоровые
    /// строки переставляются от запуска к запуску
    private static func orderedByTime(_ lines: [SubtitleLine]) -> [SubtitleLine] {
        lines
            .enumerated()
            .sorted { left, right in
                if left.element.start != right.element.start {
                    return left.element.start < right.element.start
                }
                if left.element.end != right.element.end {
                    return left.element.end < right.element.end
                }
                return left.offset < right.offset
            }
            .map { pair in pair.element }
    }

    /// DOCTYPE ищется до первого элемента: внутри текста реплики та же строка ничего не объявляет
    private static func declaresDoctype(_ text: String) -> Bool {
        guard let doctype: Range<String.Index> = text.range(of: "<!DOCTYPE", options: [.caseInsensitive]) else {
            return false
        }
        return text[text.startIndex..<doctype.lowerBound].range(of: "<[^?!]", options: .regularExpression) == nil
    }

    /// текст уже раскодирован readText, а объявление кодировки в прологе осталось: libxml2 прочитал бы
    /// байты UTF-8 как windows-1251 и выдал кракозябры
    private static func xmlWithUtf8Declaration(_ text: String) -> String {
        guard let open: Range<String.Index> = text.range(of: "<?xml"),
            let close: Range<String.Index> = text.range(of: "?>", range: open.upperBound..<text.endIndex),
            !text[text.startIndex..<open.lowerBound].contains("<")
        else {
            return text
        }
        let prolog: String = String(text[open.lowerBound..<close.lowerBound])
        let declared: String = prolog.replacingOccurrences(
            of: "encoding\\s*=\\s*(\"[^\"]*\"|'[^']*')",
            with: "encoding=\"utf-8\"",
            options: [.regularExpression, .caseInsensitive]
        )
        return text.replacingCharacters(in: open.lowerBound..<close.lowerBound, with: declared)
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

    /// SRP пишет время и с запятой, и с точкой: parseSrt сам приводит разделитель и разбирает оба написания
    private static func flexibleTime(_ input: String) -> TimeInterval? {
        try? TimeTools.parseSrt(input)
    }
}
