import Foundation

enum DocxExporter {
    /// создаёт docx с таблицей реплик и опциональной разролёвкой
    static func export(
        subtitle: ImportedSubtitle,
        outputFolder: String,
        digest: SubtitleDigest,
        language: AppLanguage,
        paths: inout OutputPathAllocator,
        roleHighlights: [String: WordHighlightColor] = [:],
        voiceSummaries: [VoiceRoleSummary] = [],
        fileSuffix: String = "",
        progress: @escaping ProgressHandler = { _ in }
    ) throws -> String {
        let name: String = TextTools.safeFileName("\(subtitle.baseName)\(fileSuffix)")
        let outputPath: String = paths.reserve(folder: outputFolder, name: name, fileExtension: "docx")
        var counter: ProgressCounter = ProgressCounter(total: subtitle.lines.count, report: progress)
        try write(
            path: outputPath,
            subtitle: subtitle,
            digest: digest,
            language: language,
            counter: &counter,
            roleHighlights: roleHighlights,
            voiceSummaries: voiceSummaries
        )
        return outputPath
    }

    /// пишет docx по готовому пути, отчитываясь о прогрессе общим счётчиком экспорта
    static func write(
        path: String,
        subtitle: ImportedSubtitle,
        digest: SubtitleDigest,
        language: AppLanguage,
        counter: inout ProgressCounter,
        roleHighlights: [String: WordHighlightColor] = [:],
        voiceSummaries: [VoiceRoleSummary] = []
    ) throws {
        let entries: [ZipArchive.Entry] = try docxEntries(
            subtitle: subtitle,
            digest: digest,
            language: language,
            roleHighlights: roleHighlights,
            voiceSummaries: voiceSummaries,
            counter: &counter
        )
        try ZipArchive.archive(entries: entries).write(to: URL(fileURLWithPath: path))
    }

    private static func docxEntries(
        subtitle: ImportedSubtitle,
        digest: SubtitleDigest,
        language: AppLanguage,
        roleHighlights: [String: WordHighlightColor],
        voiceSummaries: [VoiceRoleSummary],
        counter: inout ProgressCounter
    ) throws -> [ZipArchive.Entry] {
        [
            ZipArchive.Entry(path: "[Content_Types].xml", data: Data(contentTypes().utf8)),
            ZipArchive.Entry(path: "_rels/.rels", data: Data(rootRels().utf8)),
            ZipArchive.Entry(path: "word/_rels/document.xml.rels", data: Data(documentRels().utf8)),
            ZipArchive.Entry(path: "docProps/app.xml", data: Data(appProps().utf8)),
            ZipArchive.Entry(path: "docProps/core.xml", data: Data(coreProps().utf8)),
            ZipArchive.Entry(
                path: "word/document.xml",
                data: Data(
                    try documentXml(
                        subtitle: subtitle,
                        digest: digest,
                        language: language,
                        roleHighlights: roleHighlights,
                        voiceSummaries: voiceSummaries,
                        counter: &counter
                    ).utf8
                )
            ),
            ZipArchive.Entry(path: "word/styles.xml", data: Data(stylesXml().utf8)),
        ]
    }

    private static func documentXml(
        subtitle: ImportedSubtitle,
        digest: SubtitleDigest,
        language: AppLanguage,
        roleHighlights: [String: WordHighlightColor],
        voiceSummaries: [VoiceRoleSummary],
        counter: inout ProgressCounter
    ) throws -> String {
        var rows: String = ""
        for line in subtitle.lines {
            try counter.step()
            rows += tableRow(
                timing: TimeTools.formatClockSeconds(line.start),
                roles: line.displayRoles(language),
                replica: line.text,
                roleHighlights: roleHighlights
            )
        }

        let rolesLine: String = digest.roles.joined(separator: ", ")
        let voiceSummaryXml: String = voiceSummaries.map { summary in
            voiceSummaryParagraph(summary, language: language)
        }.joined()
        let statistics: String = roleStatistics(digest: digest)
        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body>
                \(paragraph(subtitle.baseName, bold: true, center: true, fontSize: "26", highlight: nil))
                \(paragraph(rolesLine, bold: false, center: false, fontSize: "22", highlight: nil))
                \(voiceSummaryXml)
                <w:tbl>
                  <w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="5000" w:type="pct"/></w:tblPr>
                  <w:tblGrid><w:gridCol w:w="1100"/><w:gridCol w:w="1800"/><w:gridCol w:w="8200"/></w:tblGrid>
                  \(headerRow(language: language))
                  \(rows)
                </w:tbl>
                \(paragraph("", bold: false, center: false, fontSize: "22", highlight: nil))
                \(paragraph(L.text("docx.roleStats", language), bold: true, center: false, fontSize: "22", highlight: nil))
                \(statistics)
                <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="850" w:bottom="1134" w:left="850"/></w:sectPr>
              </w:body>
            </w:document>
            """
    }

    private static func voiceSummaryParagraph(_ summary: VoiceRoleSummary, language: AppLanguage) -> String {
        let voiceTitle: String = TextTools.xmlEscape("\(L.text("voice", language)) \(summary.voice.id)")
        let roleList: String = summary.roles.joined(separator: ", ")
        let tail: String = TextTools.xmlEscape(" \(summary.voice.gender.shortTitle(language)) - \(roleList)")
        return """
            <w:p><w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/><w:highlight w:val="\(summary.voice.color.rawValue)"/></w:rPr><w:t xml:space="preserve">\(voiceTitle)</w:t></w:r><w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/></w:rPr><w:t xml:space="preserve">\(tail)</w:t></w:r></w:p>
            """
    }

    private static func headerRow(language: AppLanguage) -> String {
        """
        <w:tr>
          \(tableCell(L.text("col.timing", language), width: "1100", bold: true, alignment: "center", highlight: nil))
          \(tableCell(L.text("col.role", language), width: "1800", bold: true, alignment: "center", highlight: nil))
          \(tableCell(L.text("col.replica", language), width: "8200", bold: true, alignment: "center", highlight: nil))
        </w:tr>
        """
    }

    /// счётчики уже посчитаны при импорте: считать их здесь заново означало бы держать
    /// две реализации одной величины и однажды разойтись с тем, что показано в окне
    private static func roleStatistics(digest: SubtitleDigest) -> String {
        digest.roles
            .map { role in
                paragraph("\(role) - \(digest.counts[role, default: 0])", bold: false, center: false, fontSize: "22", highlight: nil)
            }
            .joined()
    }

    private static func tableRow(
        timing: String,
        roles: [String],
        replica: String,
        roleHighlights: [String: WordHighlightColor]
    ) -> String {
        """
        <w:tr>
          \(tableCell(timing, width: "1100", bold: false, alignment: "center", highlight: nil))
          \(roleCell(roles, roleHighlights: roleHighlights))
          \(tableCell(replica, width: "8200", bold: false, alignment: "left", highlight: nil))
        </w:tr>
        """
    }

    /// каждая роль хоровой реплики выделяется своим цветом: одна заливка на всю ячейку
    /// прятала бы то, что вторую роль читает другой голос
    private static func roleCell(_ roles: [String], roleHighlights: [String: WordHighlightColor]) -> String {
        let runs: String = roles.enumerated().map { index, role in
            let separator: String = index == 0 ? "" : run(" / ", bold: true, fontSize: "22", highlight: nil)
            return separator + run(role, bold: true, fontSize: "22", highlight: highlight(for: role, in: roleHighlights))
        }.joined()
        return """
            <w:tc><w:tcPr><w:tcW w:w="1800" w:type="dxa"/><w:vAlign w:val="top"/></w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr>\(runs)</w:p></w:tc>
            """
    }

    private static func tableCell(_ value: String, width: String, bold: Bool, alignment: String, highlight: WordHighlightColor?) -> String {
        """
        <w:tc><w:tcPr><w:tcW w:w="\(width)" w:type="dxa"/><w:vAlign w:val="top"/></w:tcPr>\(paragraph(value, bold: bold, center: false, fontSize: "22", alignment: alignment, highlight: highlight))</w:tc>
        """
    }

    /// один прогон текста: единица, из которой собираются и абзац, и ячейка с несколькими цветами
    private static func run(_ value: String, bold: Bool, fontSize: String, highlight: WordHighlightColor?) -> String {
        let boldXml: String = bold ? "<w:b/>" : ""
        let highlightXml: String = highlight.map { color in #"<w:highlight w:val="\#(color.rawValue)"/>"# } ?? ""
        let escapedLines: [String] = value.components(separatedBy: .newlines).map { line in TextTools.xmlEscape(line) }
        let textXml: String = escapedLines.enumerated().map { index, line in
            index == 0 ? #"<w:t xml:space="preserve">\#(line)</w:t>"# : #"<w:br/><w:t xml:space="preserve">\#(line)</w:t>"#
        }.joined()
        return """
            <w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="\(fontSize)"/>\(boldXml)\(highlightXml)</w:rPr>\(textXml)</w:r>
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
        let alignmentValue: String = center ? "center" : alignment
        let paragraphProperties: String = alignmentValue.isEmpty ? "" : #"<w:pPr><w:jc w:val="\#(alignmentValue)"/></w:pPr>"#
        return """
            <w:p>\(paragraphProperties)\(run(value, bold: bold, fontSize: fontSize, highlight: highlight))</w:p>
            """
    }

    private static func highlight(for role: String, in roleHighlights: [String: WordHighlightColor]) -> WordHighlightColor? {
        if let color: WordHighlightColor = roleHighlights[role] {
            return color
        }
        return roleHighlights.first { key, _ in
            key.caseInsensitiveCompare(role) == .orderedSame
        }?.value
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

    /// автор документа не заполняется: файл делает пользователь, а не автор программы,
    /// и подписывать его чужим именем в свойствах файла нечестно
    private static func coreProps() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:creator></dc:creator><cp:lastModifiedBy></cp:lastModifiedBy></cp:coreProperties>
        """
    }

    /// рамки таблицы объявлены стилем, а не повторены в каждой таблице:
    /// иначе стиль лежит в пакете мёртвым грузом
    private static func stylesXml() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="6"/><w:left w:val="single" w:sz="6"/><w:bottom w:val="single" w:sz="6"/><w:right w:val="single" w:sz="6"/><w:insideH w:val="single" w:sz="6"/><w:insideV w:val="single" w:sz="6"/></w:tblBorders></w:tblPr></w:style></w:styles>
        """
    }
}
