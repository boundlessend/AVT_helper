import Foundation

enum SubtitleExporter {
    /// экспортирует субтитры во все выбранные пользователем форматы
    static func export(subtitle: ImportedSubtitle, outputFolder: String, settings: ExportSettings) throws -> [String] {
        try FileManager.default.createDirectory(atPath: outputFolder, withIntermediateDirectories: true)
        var created: [String] = []

        if settings.exportAss {
            created.append(try exportAss(subtitle: subtitle, outputFolder: outputFolder))
        }
        if settings.exportSrt {
            created.append(contentsOf: try exportSrt(subtitle: subtitle, outputFolder: outputFolder, settings: settings))
        }
        if settings.exportVtt {
            created.append(try exportVtt(subtitle: subtitle, outputFolder: outputFolder))
        }
        if settings.exportDocx {
            created.append(try DocxExporter.export(subtitle: subtitle, outputFolder: outputFolder))
        }

        if created.isEmpty {
            throw SubtitleError.exportFailed("Не выбран ни один формат экспорта.")
        }

        return created
    }

    static func exportAss(subtitle: ImportedSubtitle, outputFolder: String) throws -> String {
        let path: String = URL(fileURLWithPath: outputFolder)
            .appendingPathComponent("\(TextTools.safeFileName(subtitle.baseName)).ass")
            .path
        var output: String = assHeader()
        for line in subtitle.lines {
            let style: String = line.style.isEmpty ? "Default" : line.style
            let role: String = line.effectiveRoles.first ?? Roles.unassigned
            output += "Dialogue: 0,\(TimeTools.formatAss(line.start)),\(TimeTools.formatAss(line.end)),\(style),\(role),0,0,0,,\(TextTools.escapeAssText(line.text))\n"
        }
        try output.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    static func exportSrt(subtitle: ImportedSubtitle, outputFolder: String, settings: ExportSettings) throws -> [String] {
        var created: [String] = []
        let safeBase: String = TextTools.safeFileName(subtitle.baseName)
        let hasMode: Bool = settings.srtFullWithRoles || settings.srtSeparateFiles || settings.srtSeparateWithRoles

        if !hasMode {
            let path: String = URL(fileURLWithPath: outputFolder).appendingPathComponent("\(safeBase) [FULL].srt").path
            try writeSrt(path: path, lines: subtitle.lines, includeRoles: false)
            created.append(path)
            return created
        }

        if settings.srtFullWithRoles {
            let path: String = URL(fileURLWithPath: outputFolder).appendingPathComponent("\(safeBase) [FULL_SQUARED].srt").path
            try writeSrt(path: path, lines: subtitle.lines, includeRoles: true)
            created.append(path)
        }

        if settings.srtSeparateFiles || settings.srtSeparateWithRoles {
            let roles: [String] = settings.selectedRoles.isEmpty ? subtitle.allRoles : Array(settings.selectedRoles).sorted()
            for role in roles {
                let roleLines: [SubtitleLine] = subtitle.lines.filter { line in
                    line.effectiveRoles.contains { current in current.caseInsensitiveCompare(role) == .orderedSame }
                }
                if roleLines.isEmpty {
                    continue
                }
                let path: String = URL(fileURLWithPath: outputFolder)
                    .appendingPathComponent("\(safeBase) [\(TextTools.safeFileName(role))].srt")
                    .path
                try writeSrt(path: path, lines: roleLines, includeRoles: settings.srtSeparateWithRoles)
                created.append(path)
            }
        }

        return created
    }

    static func exportVtt(subtitle: ImportedSubtitle, outputFolder: String) throws -> String {
        let path: String = URL(fileURLWithPath: outputFolder)
            .appendingPathComponent("\(TextTools.safeFileName(subtitle.baseName)).vtt")
            .path
        var output: String = "WEBVTT\n\n"
        for index in subtitle.lines.indices {
            let line: SubtitleLine = subtitle.lines[index]
            let prefix: String = TextTools.squareRolePrefix(line.effectiveRoles)
            let text: String = prefix.isEmpty ? line.text : "\(prefix)\n\(line.text)"
            output += "\(index + 1)\n"
            output += "\(TimeTools.formatVtt(line.start)) --> \(TimeTools.formatVtt(line.end))\n"
            output += "\(text)\n\n"
        }
        try output.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private static func writeSrt(path: String, lines: [SubtitleLine], includeRoles: Bool) throws {
        var output: String = ""
        for index in lines.indices {
            let line: SubtitleLine = lines[index]
            let prefix: String = includeRoles ? TextTools.squareRolePrefix(line.effectiveRoles) : ""
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
