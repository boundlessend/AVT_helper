import Foundation

/// экспорт прервался, но часть файлов уже записана: пути нужны интерфейсу, чтобы назвать их,
/// а причина - чтобы объяснить, почему остальных нет
struct PartialExportError: Error {
    let created: [String]
    let cause: Error
}

/// выдаёт пути для новых файлов одного прогона экспорта: не затирает ни исходный файл,
/// ни уже лежащие на диске, ни выданные ранее в этом же прогоне
struct OutputPathAllocator {
    private let sourceKey: String
    private var taken: Set<String> = []

    init(sourcePath: String) {
        sourceKey = OutputPathAllocator.key(sourcePath)
    }

    /// столько суффиксов различения перебирается, прежде чем признать, что имя занять нечем:
    /// каждая попытка это обращение к диску, и бесконечный перебор молча вешал бы экспорт
    private static let maxAttempts: Int = 10_000

    /// путь для файла с указанным именем; при занятости добавляет " (1)", " (2)" и так далее
    mutating func reserve(folder: String, name: String, fileExtension: String) throws -> String {
        let folderUrl: URL = URL(fileURLWithPath: folder)
        var attempt: Int = 0
        while attempt < OutputPathAllocator.maxAttempts {
            let suffix: String = attempt == 0 ? "" : " (\(attempt))"
            let candidate: URL = folderUrl.appendingPathComponent("\(name)\(suffix).\(fileExtension)")
            let candidateKey: String = OutputPathAllocator.key(candidate.path)
            let isFree: Bool =
                candidateKey != sourceKey
                && !taken.contains(candidateKey)
                && !FileManager.default.fileExists(atPath: candidate.path)
            if isFree {
                taken.insert(candidateKey)
                return candidate.path
            }
            attempt += 1
        }
        throw SubtitleError.tooManySimilarNames
    }

    private static func key(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path.lowercased()
    }
}

/// накопитель записи: держит в памяти только текущий кусок, поэтому длинный файл
/// не собирается строкой целиком
private struct TextSink {
    /// столько байт копится в памяти между обращениями к диску
    private static let flushBytes: Int = 64 * 1024

    private let handle: FileHandle
    private var buffer: Data = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    mutating func append(_ chunk: String) throws {
        buffer.append(contentsOf: chunk.utf8)
        if buffer.count >= TextSink.flushBytes {
            try flush()
        }
    }

    mutating func flush() throws {
        if buffer.isEmpty {
            return
        }
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }
}

enum SubtitleExporter {
    /// экспортирует субтитры во все выбранные пользователем форматы
    static func export(
        subtitle: ImportedSubtitle,
        outputFolder: String,
        settings: ExportSettings,
        digest: SubtitleDigest,
        language: AppLanguage,
        progress: @escaping ProgressHandler = { _ in }
    ) throws -> [String] {
        // существование папки проверяет интерфейс до запуска: создавать её здесь означало бы
        // молча насыпать файлов по опечатке в пути
        var paths: OutputPathAllocator = OutputPathAllocator(sourcePath: subtitle.sourcePath)

        let assPath: String? =
            settings.exportAss
            ? try paths.reserve(folder: outputFolder, name: TextTools.safeFileName(subtitle.baseName), fileExtension: "ass") : nil
        let srtJobs: [SrtJob] =
            settings.exportSrt
            ? try planSrt(subtitle: subtitle, outputFolder: outputFolder, settings: settings, language: language, paths: &paths) : []
        let vttPath: String? =
            settings.exportVtt
            ? try paths.reserve(folder: outputFolder, name: TextTools.safeFileName(subtitle.baseName), fileExtension: "vtt") : nil
        let docxPath: String? =
            settings.exportDocx
            ? try paths.reserve(folder: outputFolder, name: TextTools.safeFileName(subtitle.baseName), fileExtension: "docx") : nil

        // формат выбран, а писать нечего: это не «не выбран формат», и сказать надо именно про роли
        if settings.exportSrt && srtJobs.isEmpty {
            throw SubtitleError.exportFailed(L.text("error.noRolesForSeparateSrt", language))
        }
        if assPath == nil && srtJobs.isEmpty && vttPath == nil && docxPath == nil {
            throw SubtitleError.exportFailed(L.text("error.noFormatSelected", language))
        }

        let lineCount: Int = subtitle.lines.count
        let total: Int =
            (assPath == nil ? 0 : lineCount)
            + srtJobs.reduce(0) { sum, job in sum + job.lines.count }
            + (vttPath == nil ? 0 : lineCount)
            + (docxPath == nil ? 0 : lineCount)
        var counter: ProgressCounter = ProgressCounter(total: total, report: progress)
        var created: [String] = []

        // сбой на третьем файле из четырёх не отменяет первых двух: они уже на диске,
        // и пользователь должен узнать про них, а не разбирать папку вручную
        do {
            if let assPath: String = assPath {
                try writeAss(path: assPath, subtitle: subtitle, language: language, counter: &counter)
                created.append(assPath)
            }
            for job in srtJobs {
                try writeCues(
                    path: job.path,
                    lines: job.lines,
                    includeRoles: job.includeRoles,
                    header: "",
                    formatTime: TimeTools.formatSrt,
                    escape: { text in text },
                    counter: &counter
                )
                created.append(job.path)
            }
            if let vttPath: String = vttPath {
                try writeCues(
                    path: vttPath,
                    lines: subtitle.lines,
                    includeRoles: true,
                    header: "WEBVTT\n\n",
                    formatTime: TimeTools.formatVtt,
                    escape: escapeVttText,
                    counter: &counter
                )
                created.append(vttPath)
            }
            if let docxPath: String = docxPath {
                try DocxExporter.write(
                    path: docxPath,
                    subtitle: subtitle,
                    digest: digest,
                    language: language,
                    counter: &counter,
                    roleHighlights: settings.roleHighlights
                )
                created.append(docxPath)
            }
        } catch {
            // отмену пользователь выбрал сам, но записанные до неё файлы лежат на диске
            // ровно так же, как при ошибке, и назвать их надо тем же путём
            throw created.isEmpty ? error : PartialExportError(created: created, cause: error)
        }

        return created
    }

    private struct SrtJob {
        let path: String
        let lines: [SubtitleLine]
        let includeRoles: Bool
    }

    /// раскладывает выбранные режимы SRT в список файлов, чтобы объём работы был известен до записи
    private static func planSrt(
        subtitle: ImportedSubtitle,
        outputFolder: String,
        settings: ExportSettings,
        language: AppLanguage,
        paths: inout OutputPathAllocator
    ) throws -> [SrtJob] {
        let safeBase: String = TextTools.safeFileName(subtitle.baseName)
        let hasMode: Bool = settings.srtFullWithRoles || settings.srtSeparateFiles

        if !hasMode {
            let path: String = try paths.reserve(
                folder: outputFolder, name: fittedName(base: safeBase, part: "FULL", fileExtension: "srt"), fileExtension: "srt")
            return [SrtJob(path: path, lines: subtitle.lines, includeRoles: false)]
        }

        var jobs: [SrtJob] = []
        if settings.srtFullWithRoles {
            let path: String = try paths.reserve(
                folder: outputFolder, name: fittedName(base: safeBase, part: "FULL_SQUARED", fileExtension: "srt"), fileExtension: "srt")
            jobs.append(SrtJob(path: path, lines: subtitle.lines, includeRoles: true))
        }

        if settings.srtSeparateFiles {
            // порядок файлов должен совпадать с порядком ролей на экране, а он сравнивает по-человечески
            let roles: [String] = settings.selectedRoles.sorted { left, right in
                left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }
            for role in roles {
                let roleLines: [SubtitleLine] = subtitle.lines.filter { line in
                    line.displayRoles(language).contains { current in current.caseInsensitiveCompare(role) == .orderedSame }
                }
                if roleLines.isEmpty {
                    continue
                }
                let name: String = fittedName(base: safeBase, part: TextTools.safeFileName(role), fileExtension: "srt")
                let path: String = try paths.reserve(folder: outputFolder, name: name, fileExtension: "srt")
                jobs.append(SrtJob(path: path, lines: roleLines, includeRoles: settings.srtSeparateWithRoles))
            }
        }

        return jobs
    }

    /// запас на суффикс различения " (N)", который добавляет OutputPathAllocator
    private static let disambiguationBytes: Int = " (9999)".utf8.count

    /// имя вида "база [часть]" целиком: в предел укладывается собранное имя вместе с расширением
    /// и запасом на суффикс, а режется часть в скобках - единственная изменяемая
    private static func fittedName(base: String, part: String, fileExtension: String) -> String {
        let budget: Int = AppLimits.maxFileNameBytes - disambiguationBytes - fileExtension.utf8.count - 1
        let whole: String = "\(base) [\(part)]"
        if whole.utf8.count <= budget {
            return whole
        }
        let partBudget: Int = budget - base.utf8.count - " []".utf8.count
        if partBudget < 1 {
            // база и одна уже не помещается: режется она, но имя не становится пустым
            return truncated(whole, toBytes: budget)
        }
        return "\(base) [\(truncated(part, toBytes: partBudget))]"
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
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func writeAss(path: String, subtitle: ImportedSubtitle, language: AppLanguage, counter: inout ProgressCounter) throws {
        let script: AssScript? = subtitle.assScript
        let declared: Set<String> = declaredStyleNames(script)
        try writeStreamed(path: path) { sink in
            try sink.append(assHeader(script: script))
            for line in subtitle.lines {
                try counter.step()
                // стиль пишется только тогда, когда он объявлен в заголовке этого же файла.
                // иначе плеер получит ссылку в пустоту и молча подставит Default, не сказав об этом
                let named: String = escapeAssField(line.style)
                let style: String = declared.contains(named.lowercased()) ? named : "Default"
                let role: String = escapeAssField(line.displayRoles(language).joined(separator: TextTools.assRoleSeparator))
                // слой, отступы и эффект принадлежат исходной строке: обнулять их значит терять надписи и караоке
                try sink.append(
                    "Dialogue: \(line.layer),\(TimeTools.formatAss(line.start)),\(TimeTools.formatAss(line.end)),\(style),\(role),"
                        + "\(line.marginL),\(line.marginR),\(line.marginV),\(escapeAssField(line.effect)),"
                        + "\(TextTools.escapeAssText(line.text))\n"
                )
            }
        }
    }

    /// один цикл на SRT и WebVTT: форматы расходятся заголовком файла, видом таймкода
    /// и экранированием, а не порядком блоков
    private static func writeCues(
        path: String,
        lines: [SubtitleLine],
        includeRoles: Bool,
        header: String,
        formatTime: (TimeInterval) -> String,
        escape: (String) -> String,
        counter: inout ProgressCounter
    ) throws {
        try writeStreamed(path: path) { sink in
            try sink.append(header)
            var number: Int = 0
            for line in lines {
                try counter.step()
                // роли нет вовсе: подставленная метка ушла бы в текст и вернулась бы с импортом как настоящая роль
                let prefix: String = includeRoles ? TextTools.squareRolePrefix(line.roles) : ""
                let text: String = withoutBlankLines(line.text)
                // строка из одних тегов после чистки пуста: номер и таймкод без текста ломают блок
                if text.isEmpty {
                    continue
                }
                let body: String = prefix.isEmpty ? text : "\(prefix)\n\(text)"
                number += 1
                try sink.append("\(number)\n\(formatTime(line.start)) --> \(formatTime(line.end))\n\(escape(body))\n\n")
            }
        }
    }

    /// пустая строка внутри реплики (её даёт последовательность \N\N) разорвала бы блок SRT и VTT:
    /// при обратном чтении хвост остался бы блоком без таймкода и молча пропал
    private static func withoutBlankLines(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .filter { line in !line.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
    }

    /// W3C требует экранировать эти символы в тексте реплики; амперсанд первым, иначе он испортил бы
    /// уже подставленные сущности. вместе с ними исчезает и "-->", запрещённая в теле cue
    private static func escapeVttText(_ input: String) -> String {
        input
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// пишет файл потоком: сначала во временный файл рядом, затем переименование. запись сразу
    /// по месту оставила бы под уже занятым именем обрезанный файл, а его никто не перезапишет
    private static func writeStreamed(path: String, build: (inout TextSink) throws -> Void) throws {
        let target: URL = URL(fileURLWithPath: path)
        let temp: URL = target.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        try Data().write(to: temp)
        do {
            let handle: FileHandle = try FileHandle(forWritingTo: temp)
            var sink: TextSink = TextSink(handle: handle)
            try build(&sink)
            try sink.flush()
            try handle.close()
            try FileManager.default.moveItem(at: temp, to: target)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    /// убирает запятые из полей строки Dialogue, иначе они ломают разбор формата ASS;
    /// подстановка та же, что у импорта, поэтому имя переживает круг без изменений
    private static func escapeAssField(_ input: String) -> String {
        input.replacingOccurrences(of: ",", with: "_")
    }

    /// заголовок исходного файла, если он был: разрешение кадра и определения стилей
    /// принадлежат ему, а не нам. своим заголовком подменяется только отсутствующий
    private static func assHeader(script: AssScript?) -> String {
        guard let script: AssScript = script else {
            return defaultAssHeader
        }
        // события пишутся как v4+, поэтому и заголовок объявляется как v4+: блок стилей SSA
        // рядом с полем Layer давал бы гибрид, который каждый плеер понимает по-своему
        let legacy: Bool = !script.stylesSection.lowercased().contains("v4+")
        let infoLines: [String] = legacy ? upgradedScriptInfo(script.scriptInfo) : script.scriptInfo
        let info: String = infoLines.isEmpty ? defaultScriptInfo : infoLines.joined(separator: "\n")
        let carried: [String] = legacy ? upgradedStyleLines(script.styles) : script.styles.map(sanitizedStyleLine)
        let styles: String = styleLinesWithDefault(carried).joined(separator: "\n")
        let section: String = legacy || script.stylesSection.isEmpty ? "[V4+ Styles]" : script.stylesSection
        return """
            [Script Info]
            \(info)

            \(section)
            \(styles)

            [Events]
            \(assEventsFormatLine)

            """
    }

    /// ScriptType обязан совпадать с тем, что записано ниже: события идут в формате v4+
    private static func upgradedScriptInfo(_ lines: [String]) -> [String] {
        lines.map { line in
            line.range(of: "ScriptType:", options: [.caseInsensitive, .anchored]) != nil ? "ScriptType: v4.00+" : line
        }
    }

    /// переводит блок стилей SSA в v4+: порядок полей объявляется заново, TertiaryColour занимает
    /// место OutlineColour, а выравнивание переходит из нумерации SSA в нумерацию ASS
    private static func upgradedStyleLines(_ lines: [String]) -> [String] {
        let declared: [String] = lines.lazy.compactMap(styleFieldOrder).first ?? ssaStyleFields
        var result: [String] = []
        var wroteFormat: Bool = false
        for line in lines {
            if styleFieldOrder(line) != nil {
                result.append(assStyleFormatLine)
                wroteFormat = true
            } else if styleName(line) != nil {
                result.append(upgradedStyleLine(line, fields: declared))
            } else {
                result.append(line)
            }
        }
        return wroteFormat ? result : [assStyleFormatLine] + result
    }

    /// одна строка Style в порядке полей v4+; строка, не совпавшая с объявленным порядком,
    /// переносится как есть - угадывать её значения опаснее, чем оставить их плееру
    private static func upgradedStyleLine(_ line: String, fields: [String]) -> String {
        let values: [String] = String(line.dropFirst("Style:".count))
            .components(separatedBy: ",")
            .map { value in value.trimmingCharacters(in: .whitespaces) }
        guard values.count == fields.count else {
            return sanitizedStyleLine(line)
        }
        var byField: [String: String] = [:]
        for (field, value) in zip(fields, values) {
            byField[field == "tertiarycolour" ? "outlinecolour" : field] = value
        }
        guard let name: String = byField["name"], !name.isEmpty else {
            return sanitizedStyleLine(line)
        }
        byField["name"] = escapeAssField(name)
        byField["alignment"] = assAlignment(byField["alignment"] ?? defaultStyleValues["alignment"] ?? "2")
        let converted: [String] = assStyleFields.map { field in byField[field] ?? defaultStyleValues[field] ?? "0" }
        return "Style: \(converted.joined(separator: ","))"
    }

    /// SSA считает выравнивание иначе: 5-7 это верх, 9-11 середина. ASS нумерует позиции
    /// как цифровой блок клавиатуры, и неизвестное значение остаётся нетронутым
    private static func assAlignment(_ value: String) -> String {
        let ssaToAss: [String: String] = ["1": "1", "2": "2", "3": "3", "5": "7", "6": "8", "7": "9", "9": "4", "10": "5", "11": "6"]
        return ssaToAss[value] ?? value
    }

    /// строка Dialogue с необъявленным стилем заменяется на Default, поэтому сам Default
    /// обязан быть объявлен: иначе подмена ссылается на стиль, которого в заголовке нет
    private static func styleLinesWithDefault(_ lines: [String]) -> [String] {
        if lines.contains(where: { line in styleName(line)?.lowercased() == "default" }) {
            return lines
        }
        var result: [String] = lines
        while let last: String = result.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            result.removeLast()
        }
        let fields: [String] = lines.lazy.compactMap(styleFieldOrder).first ?? assStyleFields
        result.append(defaultStyleLine(fields: fields))
        return result
    }

    /// наш стиль Default в том порядке полей, который объявляет блок стилей этого файла
    private static func defaultStyleLine(fields: [String]) -> String {
        let values: [String] = fields.map { field in defaultStyleValues[field] ?? "0" }
        return "Style: \(values.joined(separator: ","))"
    }

    /// имена стилей, объявленных заголовком, в нижнем регистре для сравнения
    private static func declaredStyleNames(_ script: AssScript?) -> Set<String> {
        guard let script: AssScript = script else {
            return ["default"]
        }
        let names: [String] = script.styles.compactMap { line in styleName(line)?.lowercased() }
        return Set(names + ["default"])
    }

    /// имя стиля из строки определения, очищенное так же, как в строке Dialogue;
    /// nil означает, что это не строка Style
    private static func styleName(_ line: String) -> String? {
        guard line.range(of: "Style:", options: [.caseInsensitive, .anchored]) != nil else {
            return nil
        }
        let payload: String = String(line.dropFirst("Style:".count))
        guard let name: Substring = payload.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first else {
            return nil
        }
        return escapeAssField(String(name).trimmingCharacters(in: .whitespaces))
    }

    /// порядок полей блока стилей, объявленный строкой Format; nil означает, что это не строка Format
    private static func styleFieldOrder(_ line: String) -> [String]? {
        guard line.range(of: "Format:", options: [.caseInsensitive, .anchored]) != nil else {
            return nil
        }
        return line.dropFirst("Format:".count)
            .components(separatedBy: ",")
            .map { field in field.trimmingCharacters(in: .whitespaces).lowercased() }
    }

    /// имя стиля в определении чистится ровно так же, как в строке Dialogue:
    /// иначе после чистки одно перестаёт совпадать с другим
    private static func sanitizedStyleLine(_ line: String) -> String {
        guard line.range(of: "Style:", options: [.caseInsensitive, .anchored]) != nil else {
            return line
        }
        let payload: String = String(line.dropFirst("Style:".count))
        let parts: [Substring] = payload.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return line
        }
        let name: String = escapeAssField(String(parts[0]).trimmingCharacters(in: .whitespaces))
        return "Style: \(name),\(parts[1])"
    }

    /// порядок полей блока стилей v4+: в нём пишется и наш заголовок, и переведённый из SSA
    private static let assStyleFields: [String] = [
        "name", "fontname", "fontsize", "primarycolour", "secondarycolour", "outlinecolour", "backcolour",
        "bold", "italic", "underline", "strikeout", "scalex", "scaley", "spacing", "angle",
        "borderstyle", "outline", "shadow", "alignment", "marginl", "marginr", "marginv", "encoding",
    ]

    /// порядок полей блока стилей SSA v4, когда исходник не объявил свой строкой Format
    private static let ssaStyleFields: [String] = [
        "name", "fontname", "fontsize", "primarycolour", "secondarycolour", "tertiarycolour", "backcolour",
        "bold", "italic", "borderstyle", "outline", "shadow", "alignment", "marginl", "marginr", "marginv",
        "alphalevel", "encoding",
    ]

    /// значения нашего стиля Default по именам полей: ими добираются поля, которых в исходном
    /// блоке стилей не было
    private static let defaultStyleValues: [String: String] = [
        "name": "Default", "fontname": "Arial", "fontsize": "48",
        "primarycolour": "&H00FFFFFF", "secondarycolour": "&H000000FF", "outlinecolour": "&H00000000", "backcolour": "&H64000000",
        "bold": "0", "italic": "0", "underline": "0", "strikeout": "0",
        "scalex": "100", "scaley": "100", "spacing": "0", "angle": "0",
        "borderstyle": "1", "outline": "2", "shadow": "0", "alignment": "2",
        "marginl": "20", "marginr": "20", "marginv": "40", "encoding": "1",
    ]

    private static let assStyleFormatLine: String = """
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        """

    private static let assEventsFormatLine: String = """
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        """

    private static let defaultScriptInfo: String = """
        ScriptType: v4.00+
        Collisions: Normal
        PlayResX: 1920
        PlayResY: 1080
        ScaledBorderAndShadow: yes
        WrapStyle: 0
        Timer: 100.0000
        """

    private static let defaultAssHeader: String = """
        [Script Info]
        \(defaultScriptInfo)

        [V4+ Styles]
        \(assStyleFormatLine)
        \(defaultStyleLine(fields: assStyleFields))

        [Events]
        \(assEventsFormatLine)

        """
}
