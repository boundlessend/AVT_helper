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

    /// путь для файла с указанным именем; при занятости добавляет " (1)", " (2)" и так далее
    mutating func reserve(folder: String, name: String, fileExtension: String) -> String {
        let folderUrl: URL = URL(fileURLWithPath: folder)
        var attempt: Int = 0
        while true {
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
    }

    private static func key(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path.lowercased()
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
            ? paths.reserve(folder: outputFolder, name: TextTools.safeFileName(subtitle.baseName), fileExtension: "ass") : nil
        let srtJobs: [SrtJob] =
            settings.exportSrt
            ? planSrt(subtitle: subtitle, outputFolder: outputFolder, settings: settings, language: language, paths: &paths) : []
        let vttPath: String? =
            settings.exportVtt
            ? paths.reserve(folder: outputFolder, name: TextTools.safeFileName(subtitle.baseName), fileExtension: "vtt") : nil
        let docxPath: String? =
            settings.exportDocx
            ? paths.reserve(folder: outputFolder, name: TextTools.safeFileName(subtitle.baseName), fileExtension: "docx") : nil

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
                try writeSrt(path: job.path, lines: job.lines, includeRoles: job.includeRoles, language: language, counter: &counter)
                created.append(job.path)
            }
            if let vttPath: String = vttPath {
                try writeVtt(path: vttPath, subtitle: subtitle, language: language, counter: &counter)
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
        } catch is CancellationError {
            // отмену пользователь выбрал сам: она не ошибка и не нуждается в объяснении
            throw CancellationError()
        } catch {
            throw created.isEmpty ? error : PartialExportError(created: created, cause: error)
        }

        return created
    }

    static func exportAss(
        subtitle: ImportedSubtitle,
        outputFolder: String,
        language: AppLanguage,
        paths: inout OutputPathAllocator
    ) throws -> String {
        let path: String = paths.reserve(folder: outputFolder, name: TextTools.safeFileName(subtitle.baseName), fileExtension: "ass")
        var counter: ProgressCounter = ProgressCounter(total: subtitle.lines.count, report: { _ in })
        try writeAss(path: path, subtitle: subtitle, language: language, counter: &counter)
        return path
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
    ) -> [SrtJob] {
        let safeBase: String = TextTools.safeFileName(subtitle.baseName)
        let hasMode: Bool = settings.srtFullWithRoles || settings.srtSeparateFiles

        if !hasMode {
            let path: String = paths.reserve(folder: outputFolder, name: "\(safeBase) [FULL]", fileExtension: "srt")
            return [SrtJob(path: path, lines: subtitle.lines, includeRoles: false)]
        }

        var jobs: [SrtJob] = []
        if settings.srtFullWithRoles {
            let path: String = paths.reserve(folder: outputFolder, name: "\(safeBase) [FULL_SQUARED]", fileExtension: "srt")
            jobs.append(SrtJob(path: path, lines: subtitle.lines, includeRoles: true))
        }

        if settings.srtSeparateFiles {
            let roles: [String] = Array(settings.selectedRoles).sorted()
            for role in roles {
                let roleLines: [SubtitleLine] = subtitle.lines.filter { line in
                    line.displayRoles(language).contains { current in current.caseInsensitiveCompare(role) == .orderedSame }
                }
                if roleLines.isEmpty {
                    continue
                }
                let path: String = paths.reserve(
                    folder: outputFolder, name: "\(safeBase) [\(TextTools.safeFileName(role))]", fileExtension: "srt")
                jobs.append(SrtJob(path: path, lines: roleLines, includeRoles: settings.srtSeparateWithRoles))
            }
        }

        return jobs
    }

    private static func writeAss(path: String, subtitle: ImportedSubtitle, language: AppLanguage, counter: inout ProgressCounter) throws {
        let script: AssScript? = subtitle.assScript
        let declared: Set<String> = declaredStyleNames(script)
        var output: String = assHeader(script: script)
        for line in subtitle.lines {
            try counter.step()
            // стиль пишется только тогда, когда он объявлен в заголовке этого же файла.
            // иначе плеер получит ссылку в пустоту и молча подставит Default, не сказав об этом
            let named: String = escapeAssField(line.style)
            let style: String = declared.contains(named.lowercased()) ? named : "Default"
            let role: String = escapeAssField(line.displayRoles(language).joined(separator: TextTools.assRoleSeparator))
            output +=
                "Dialogue: 0,\(TimeTools.formatAss(line.start)),\(TimeTools.formatAss(line.end)),\(style),\(role),0,0,0,,\(TextTools.escapeAssText(line.text))\n"
        }
        try output.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func writeVtt(path: String, subtitle: ImportedSubtitle, language: AppLanguage, counter: inout ProgressCounter) throws {
        var output: String = "WEBVTT\n\n"
        for index in subtitle.lines.indices {
            try counter.step()
            let line: SubtitleLine = subtitle.lines[index]
            let prefix: String = TextTools.squareRolePrefix(line.displayRoles(language))
            let text: String = prefix.isEmpty ? line.text : "\(prefix)\n\(line.text)"
            output += "\(index + 1)\n"
            output += "\(TimeTools.formatVtt(line.start)) --> \(TimeTools.formatVtt(line.end))\n"
            output += "\(text)\n\n"
        }
        try output.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// убирает запятые из полей строки Dialogue, иначе они ломают разбор формата ASS;
    /// подстановка та же, что у импорта, поэтому имя переживает круг без изменений
    private static func escapeAssField(_ input: String) -> String {
        input.replacingOccurrences(of: ",", with: "_")
    }

    private static func writeSrt(
        path: String,
        lines: [SubtitleLine],
        includeRoles: Bool,
        language: AppLanguage,
        counter: inout ProgressCounter
    ) throws {
        var output: String = ""
        for index in lines.indices {
            try counter.step()
            let line: SubtitleLine = lines[index]
            let prefix: String = includeRoles ? TextTools.squareRolePrefix(line.displayRoles(language)) : ""
            let text: String = prefix.isEmpty ? line.text : "\(prefix)\n\(line.text)"
            output += "\(index + 1)\n"
            output += "\(TimeTools.formatSrt(line.start)) --> \(TimeTools.formatSrt(line.end))\n"
            output += "\(text)\n\n"
        }
        try output.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// заголовок исходного файла, если он был: разрешение кадра и определения стилей
    /// принадлежат ему, а не нам. своим заголовком подменяется только отсутствующий
    private static func assHeader(script: AssScript?) -> String {
        guard let script: AssScript = script else {
            return defaultAssHeader
        }
        let info: String = script.scriptInfo.isEmpty ? defaultScriptInfo : script.scriptInfo.joined(separator: "\n")
        let styles: String = script.styles.map(sanitizedStyleLine).joined(separator: "\n")
        let section: String = script.stylesSection.isEmpty ? "[V4+ Styles]" : script.stylesSection
        return """
            [Script Info]
            \(info)

            \(section)
            \(styles)

            [Events]
            Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text

            """
    }

    /// имена стилей, объявленных заголовком, в нижнем регистре для сравнения
    private static func declaredStyleNames(_ script: AssScript?) -> Set<String> {
        guard let script: AssScript = script else {
            return ["default"]
        }
        let names: [String] = script.styles.compactMap { line in
            guard line.range(of: "Style:", options: [.caseInsensitive, .anchored]) != nil else {
                return nil
            }
            let payload: String = String(line.dropFirst("Style:".count))
            guard let name: Substring = payload.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first else {
                return nil
            }
            return escapeAssField(String(name).trimmingCharacters(in: .whitespaces)).lowercased()
        }
        return Set(names + ["default"])
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

    private static let defaultScriptInfo: String = """
        ScriptType: v4.00+
        Collisions: Normal
        PlayResX: 1920
        PlayResY: 1080
        Timer: 100.0000
        """

    private static let defaultAssHeader: String = """
        [Script Info]
        \(defaultScriptInfo)

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H64000000,0,0,0,0,100,100,0,0,1,2,0,2,20,20,40,1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text

        """
}
