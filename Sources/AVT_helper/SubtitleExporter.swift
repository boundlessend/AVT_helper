import Foundation

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
    static func export(subtitle: ImportedSubtitle, outputFolder: String, settings: ExportSettings, language: AppLanguage) throws -> [String] {
        try FileManager.default.createDirectory(atPath: outputFolder, withIntermediateDirectories: true)
        var paths: OutputPathAllocator = OutputPathAllocator(sourcePath: subtitle.sourcePath)
        var created: [String] = []

        if settings.exportAss {
            created.append(try exportAss(subtitle: subtitle, outputFolder: outputFolder, language: language, paths: &paths))
        }
        if settings.exportSrt {
            created.append(
                contentsOf: try exportSrt(subtitle: subtitle, outputFolder: outputFolder, settings: settings, language: language, paths: &paths)
            )
        }
        if settings.exportVtt {
            created.append(try exportVtt(subtitle: subtitle, outputFolder: outputFolder, language: language, paths: &paths))
        }
        if settings.exportDocx {
            created.append(try DocxExporter.export(subtitle: subtitle, outputFolder: outputFolder, language: language, paths: &paths))
        }

        if created.isEmpty {
            throw SubtitleError.exportFailed(L.text("error.noFormatSelected", language))
        }

        return created
    }

    static func exportAss(subtitle: ImportedSubtitle, outputFolder: String, language: AppLanguage, paths: inout OutputPathAllocator) throws -> String {
        let path: String = paths.reserve(folder: outputFolder, name: TextTools.safeFileName(subtitle.baseName), fileExtension: "ass")
        var output: String = assHeader()
        for line in subtitle.lines {
            let style: String = escapeAssField(line.style.isEmpty ? "Default" : line.style)
            let role: String = escapeAssField(line.displayRoles(language)[0])
            output += "Dialogue: 0,\(TimeTools.formatAss(line.start)),\(TimeTools.formatAss(line.end)),\(style),\(role),0,0,0,,\(TextTools.escapeAssText(line.text))\n"
        }
        try output.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    static func exportSrt(
        subtitle: ImportedSubtitle,
        outputFolder: String,
        settings: ExportSettings,
        language: AppLanguage,
        paths: inout OutputPathAllocator
    ) throws -> [String] {
        var created: [String] = []
        let safeBase: String = TextTools.safeFileName(subtitle.baseName)
        let hasMode: Bool = settings.srtFullWithRoles || settings.srtSeparateFiles || settings.srtSeparateWithRoles

        if !hasMode {
            let path: String = paths.reserve(folder: outputFolder, name: "\(safeBase) [FULL]", fileExtension: "srt")
            try writeSrt(path: path, lines: subtitle.lines, includeRoles: false, language: language)
            created.append(path)
            return created
        }

        if settings.srtFullWithRoles {
            let path: String = paths.reserve(folder: outputFolder, name: "\(safeBase) [FULL_SQUARED]", fileExtension: "srt")
            try writeSrt(path: path, lines: subtitle.lines, includeRoles: true, language: language)
            created.append(path)
        }

        if settings.srtSeparateFiles || settings.srtSeparateWithRoles {
            let roles: [String] = settings.selectedRoles.isEmpty ? subtitle.allRoles(language) : Array(settings.selectedRoles).sorted()
            for role in roles {
                let roleLines: [SubtitleLine] = subtitle.lines.filter { line in
                    line.displayRoles(language).contains { current in current.caseInsensitiveCompare(role) == .orderedSame }
                }
                if roleLines.isEmpty {
                    continue
                }
                let path: String = paths.reserve(folder: outputFolder, name: "\(safeBase) [\(TextTools.safeFileName(role))]", fileExtension: "srt")
                try writeSrt(path: path, lines: roleLines, includeRoles: settings.srtSeparateWithRoles, language: language)
                created.append(path)
            }
        }

        return created
    }

    static func exportVtt(subtitle: ImportedSubtitle, outputFolder: String, language: AppLanguage, paths: inout OutputPathAllocator) throws -> String {
        let path: String = paths.reserve(folder: outputFolder, name: TextTools.safeFileName(subtitle.baseName), fileExtension: "vtt")
        var output: String = "WEBVTT\n\n"
        for index in subtitle.lines.indices {
            let line: SubtitleLine = subtitle.lines[index]
            let prefix: String = TextTools.squareRolePrefix(line.displayRoles(language))
            let text: String = prefix.isEmpty ? line.text : "\(prefix)\n\(line.text)"
            output += "\(index + 1)\n"
            output += "\(TimeTools.formatVtt(line.start)) --> \(TimeTools.formatVtt(line.end))\n"
            output += "\(text)\n\n"
        }
        try output.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    /// убирает запятые из полей строки Dialogue, иначе они ломают разбор формата ASS
    private static func escapeAssField(_ input: String) -> String {
        input.replacingOccurrences(of: ",", with: " ")
    }

    private static func writeSrt(path: String, lines: [SubtitleLine], includeRoles: Bool, language: AppLanguage) throws {
        var output: String = ""
        for index in lines.indices {
            let line: SubtitleLine = lines[index]
            let prefix: String = includeRoles ? TextTools.squareRolePrefix(line.displayRoles(language)) : ""
            let text: String = prefix.isEmpty ? line.text : "\(prefix)\n\(line.text)"
            output += "\(index + 1)\n"
            output += "\(TimeTools.formatSrt(line.start)) --> \(TimeTools.formatSrt(line.end))\n"
            output += "\(text)\n\n"
        }
        try output.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func assHeader() -> String {
        """
        [Script Info]
        ScriptType: v4.00+
        Collisions: Normal
        PlayResX: 1920
        PlayResY: 1080
        Timer: 100.0000

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H64000000,0,0,0,0,100,100,0,0,1,2,0,2,20,20,40,1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text

        """
    }
}
