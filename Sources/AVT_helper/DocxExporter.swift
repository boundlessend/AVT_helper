import Foundation

enum DocxExporter {
    static func export(
        subtitle: ImportedSubtitle,
        outputFolder: String,
        roleHighlights: [String: WordHighlightColor] = [:],
        voiceSummaries: [VoiceRoleSummary] = [],
        fileSuffix: String = ""
    ) throws -> String {
        let safeBase: String = TextTools.safeFileName(subtitle.baseName)
        let outputPath: String = URL(fileURLWithPath: outputFolder).appendingPathComponent("\(safeBase)\(fileSuffix).docx").path
        let tempRoot: URL = FileManager.default.temporaryDirectory.appendingPathComponent("AVT_helper_docx_\(UUID().uuidString)")
        try createStructure(root: tempRoot)
        try writeDocxFiles(root: tempRoot, subtitle: subtitle, roleHighlights: roleHighlights, voiceSummaries: voiceSummaries)
        try zipDocx(root: tempRoot, outputPath: outputPath)
        try? FileManager.default.removeItem(at: tempRoot)
        return outputPath
    }

    private static func createStructure(root: URL) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("word/_rels"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docProps"), withIntermediateDirectories: true)
    }

    private static func writeDocxFiles(
        root: URL,
        subtitle: ImportedSubtitle,
        roleHighlights: [String: WordHighlightColor],
        voiceSummaries: [VoiceRoleSummary]
    ) throws {
        try contentTypes().write(to: root.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        try rootRels().write(to: root.appendingPathComponent("_rels/.rels"), atomically: true, encoding: .utf8)
        try documentRels().write(to: root.appendingPathComponent("word/_rels/document.xml.rels"), atomically: true, encoding: .utf8)
        try appProps().write(to: root.appendingPathComponent("docProps/app.xml"), atomically: true, encoding: .utf8)
        try coreProps().write(to: root.appendingPathComponent("docProps/core.xml"), atomically: true, encoding: .utf8)
        try documentXml(subtitle: subtitle, roleHighlights: roleHighlights, voiceSummaries: voiceSummaries)
            .write(to: root.appendingPathComponent("word/document.xml"), atomically: true, encoding: .utf8)
        try stylesXml().write(to: root.appendingPathComponent("word/styles.xml"), atomically: true, encoding: .utf8)
    }

    private static func zipDocx(root: URL, outputPath: String) throws {
        if FileManager.default.fileExists(atPath: outputPath) {
            try FileManager.default.removeItem(atPath: outputPath)
        }
        let process: Process = Process()
        process.currentDirectoryURL = root
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", outputPath, "."]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw SubtitleError.exportFailed("zip завершился с кодом \(process.terminationStatus)")
        }
    }

    private static func documentXml(
        subtitle: ImportedSubtitle,
        roleHighlights: [String: WordHighlightColor],
        voiceSummaries: [VoiceRoleSummary]
    ) -> String {
        let rows: String = subtitle.lines.map { line in
            let lineHighlight: WordHighlightColor? = highlightForRoles(line.effectiveRoles, roleHighlights: roleHighlights)
            return tableRow(
                timing: TimeTools.formatClockSeconds(line.start),
                role: line.effectiveRoles.joined(separator: " / "),
                replica: line.text,
                roleHighlight: lineHighlight
            )
        }.joined()

        let rolesLine: String = subtitle.allRoles.joined(separator: ", ")
        let voiceSummaryXml: String = voiceSummaries.map { summary in
            voiceSummaryParagraph(summary)
        }.joined()
        let statistics: String = roleStatistics(subtitle: subtitle)
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            \(paragraph(subtitle.baseName, bold: true, center: true, fontSize: "26", highlight: nil))
            \(paragraph(rolesLine, bold: false, center: false, fontSize: "22", highlight: nil))
            \(voiceSummaryXml)
            <w:tbl>
              <w:tblPr><w:tblW w:w="5000" w:type="pct"/><w:tblBorders><w:top w:val="single" w:sz="6"/><w:left w:val="single" w:sz="6"/><w:bottom w:val="single" w:sz="6"/><w:right w:val="single" w:sz="6"/><w:insideH w:val="single" w:sz="6"/><w:insideV w:val="single" w:sz="6"/></w:tblBorders></w:tblPr>
              <w:tblGrid><w:gridCol w:w="1100"/><w:gridCol w:w="1800"/><w:gridCol w:w="8200"/></w:tblGrid>
              \(headerRow())
              \(rows)
            </w:tbl>
            \(paragraph("", bold: false, center: false, fontSize: "22", highlight: nil))
            \(paragraph("Статистика по ролям", bold: true, center: false, fontSize: "22", highlight: nil))
            \(statistics)
            <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="850" w:bottom="1134" w:left="850"/></w:sectPr>
          </w:body>
        </w:document>
        """
    }

    private static func voiceSummaryParagraph(_ summary: VoiceRoleSummary) -> String {
        let voiceTitle: String = TextTools.xmlEscape("Голос \(summary.voice.id)")
        let roleList: String = summary.roles.joined(separator: ", ")
        let tail: String = TextTools.xmlEscape(" \(summary.voice.gender.shortTitle) - \(roleList)")
        return """
        <w:p><w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/><w:highlight w:val="\(summary.voice.color.wordValue)"/></w:rPr><w:t xml:space="preserve">\(voiceTitle)</w:t></w:r><w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/></w:rPr><w:t xml:space="preserve">\(tail)</w:t></w:r></w:p>
        """
    }

    private static func headerRow() -> String {
        """
        <w:tr>
          \(tableCell("Тайминг", width: "1100", bold: true, alignment: "center", highlight: nil))
          \(tableCell("Роль", width: "1800", bold: true, alignment: "center", highlight: nil))
          \(tableCell("Реплика", width: "8200", bold: true, alignment: "center", highlight: nil))
        </w:tr>
        """
    }

    private static func roleStatistics(subtitle: ImportedSubtitle) -> String {
        let counts: [(String, Int)] = Dictionary(grouping: subtitle.lines.flatMap { line in line.effectiveRoles }, by: { role in role })
            .map { role, values in (role, values.count) }
            .sorted { left, right in
                left.0.localizedCaseInsensitiveCompare(right.0) == .orderedAscending
            }
        return counts.map { role, count in
            paragraph("\(role) - \(count)", bold: false, center: false, fontSize: "22", highlight: nil)
        }.joined()
    }

    private static func tableRow(timing: String, role: String, replica: String, roleHighlight: WordHighlightColor?) -> String {
        """
        <w:tr>
          \(tableCell(timing, width: "1100", bold: false, alignment: "center", highlight: nil))
          \(tableCell(role, width: "1800", bold: true, alignment: "center", highlight: roleHighlight))
          \(tableCell(replica, width: "8200", bold: false, alignment: "left", highlight: nil))
        </w:tr>
        """
    }

    private static func tableCell(_ value: String, width: String, bold: Bool, alignment: String, highlight: WordHighlightColor?) -> String {
        """
        <w:tc><w:tcPr><w:tcW w:w="\(width)" w:type="dxa"/><w:vAlign w:val="top"/></w:tcPr>\(paragraph(value, bold: bold, center: false, fontSize: "22", alignment: alignment, highlight: highlight))</w:tc>
        """
    }

    private static func paragraph(
        _ value: String,
        bold: Bool,
        center: Bool,
        fontSize: String,
        alignment: String = "",
        highlight: WordHighlightColor?
    ) -> String {
        let boldXml: String = bold ? "<w:b/>" : ""
        let highlightXml: String = highlight.map { color in #"<w:highlight w:val="\#(color.wordValue)"/>"# } ?? ""
        let alignmentValue: String = center ? "center" : alignment
        let paragraphProperties: String = alignmentValue.isEmpty ? "" : #"<w:pPr><w:jc w:val="\#(alignmentValue)"/></w:pPr>"#
        let escapedLines: [String] = value.components(separatedBy: .newlines).map { line in TextTools.xmlEscape(line) }
        let textXml: String = escapedLines.enumerated().map { index, line in
            index == 0 ? #"<w:t xml:space="preserve">\#(line)</w:t>"# : #"<w:br/><w:t xml:space="preserve">\#(line)</w:t>"#
        }.joined()
        return """
        <w:p>\(paragraphProperties)<w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="\(fontSize)"/>\(boldXml)\(highlightXml)</w:rPr>\(textXml)</w:r></w:p>
        """
    }

    private static func highlightForRoles(_ roles: [String], roleHighlights: [String: WordHighlightColor]) -> WordHighlightColor? {
        for role in roles {
            if let color: WordHighlightColor = roleHighlights[role] {
                return color
            }
            if let color: WordHighlightColor = roleHighlights.first(where: { key, _ in
                key.caseInsensitiveCompare(role) == .orderedSame
            })?.value {
                return color
            }
        }
        return nil
    }

    private static func contentTypes() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
          <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
          <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        </Types>
        """
    }

    private static func rootRels() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
          <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
        """
    }

    private static func documentRels() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """
    }

    private static func appProps() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>AVT_helper</Application></Properties>
        """
    }

    private static func coreProps() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:creator>@boundlessend</dc:creator></cp:coreProperties>
        """
    }

    private static func stylesXml() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/></w:style></w:styles>
        """
    }
}
