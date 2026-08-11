import Foundation

enum SubtitleExporter {
    /// экспортирует субтитры во все выбранные пользователем форматы
    static func export(subtitle: ImportedSubtitle, outputFolder: String, settings: ExportSettings, language: AppLanguage) throws -> [String] {
        try FileManager.default.createDirectory(atPath: outputFolder, withIntermediateDirectories: true)
        var created: [String] = []

        if settings.exportAss {
            created.append(try exportAss(subtitle: subtitle, outputFolder: outputFolder, language: language))
        }
        if settings.exportSrt {
            created.append(contentsOf: try exportSrt(subtitle: subtitle, outputFolder: outputFolder, settings: settings, language: language))
        }
        if settings.exportVtt {
            created.append(try exportVtt(subtitle: subtitle, outputFolder: outputFolder, language: language))
        }
        if settings.exportDocx {
            created.append(try DocxExporter.export(subtitle: subtitle, outputFolder: outputFolder, language: language))
        }

        if created.isEmpty {
            throw SubtitleError.exportFailed(L.text("error.noFormatSelected", language))
        }

        return created
    }

    static func exportAss(subtitle: ImportedSubtitle, outputFolder: String, language: AppLanguage) throws -> String {
        let path: String = safeOutputPath(
            URL(fileURLWithPath: outputFolder)
                .appendingPathComponent("\(TextTools.safeFileName(subtitle.baseName)).ass")
                .path,
            sourcePath: subtitle.sourcePath
        )
        var output: String = assHeader()
        for line in subtitle.lines {
            let style: String = escapeAssField(line.style.isEmpty ? "Default" : line.style)
            let role: String = escapeAssField(line.displayRoles(language)[0])
            output += "Dialogue: 0,\(TimeTools.formatAss(line.start)),\(TimeTools.formatAss(line.end)),\(style),\(role),0,0,0,,\(TextTools.escapeAssText(line.text))\n"
        }
        try output.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    static func exportSrt(subtitle: ImportedSubtitle, outputFolder: String, settings: ExportSettings, language: AppLanguage) throws -> [String] {
        var created: [String] = []
        let safeBase: String = TextTools.safeFileName(subtitle.baseName)
        let hasMode: Bool = settings.srtFullWithRoles || settings.srtSeparateFiles || settings.srtSeparateWithRoles

        if !hasMode {
            let path: String = safeOutputPath(
                URL(fileURLWithPath: outputFolder).appendingPathComponent("\(safeBase) [FULL].srt").path,
                sourcePath: subtitle.sourcePath
            )
            try writeSrt(path: path, lines: subtitle.lines, includeRoles: false, language: language)
            created.append(path)
            return created
        }

        if settings.srtFullWithRoles {
            let path: String = safeOutputPath(
                URL(fileURLWithPath: outputFolder).appendingPathComponent("\(safeBase) [FULL_SQUARED].srt").path,
                sourcePath: subtitle.sourcePath
            )
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
                let path: String = safeOutputPath(
                    URL(fileURLWithPath: outputFolder)
                        .appendingPathComponent("\(safeBase) [\(TextTools.safeFileName(role))].srt")
                        .path,
                    sourcePath: subtitle.sourcePath
                )
                try writeSrt(path: path, lines: roleLines, includeRoles: settings.srtSeparateWithRoles, language: language)
                created.append(path)
            }
        }

        return created
    }

    static func exportVtt(subtitle: ImportedSubtitle, outputFolder: String, language: AppLanguage) throws -> String {
        let path: String = safeOutputPath(
            URL(fileURLWithPath: outputFolder)
                .appendingPathComponent("\(TextTools.safeFileName(subtitle.baseName)).vtt")
                .path,
            sourcePath: subtitle.sourcePath
        )
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

    /// не даёт экспорту затереть импортированный исходный файл: при совпадении путей добавляет " (1)" к имени
    static func safeOutputPath(_ path: String, sourcePath: String) -> String {
        let target: String = URL(fileURLWithPath: path).standardizedFileURL.path
        guard target.caseInsensitiveCompare(sourcePath) == .orderedSame else {
            return path
        }
        let url: URL = URL(fileURLWithPath: path)
        let base: String = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent()
            .appendingPathComponent("\(base) (1).\(url.pathExtension)")
            .path
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
