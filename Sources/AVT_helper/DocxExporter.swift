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
        let outputPath: String = try paths.reserve(folder: outputFolder, name: name, fileExtension: "docx")
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
        try Task.checkCancellation()
        let archive: Data = ZipArchive.archive(entries: entries)
        try Task.checkCancellation()
        // запись идёт во временный файл рядом, а на место встаёт переименованием: оборванная запись
        // не оставит обрезанный docx, а появившийся тем временем чужой файл не будет затёрт,
        // потому что moveItem на занятое имя падает, а не перезаписывает
        let target: URL = URL(fileURLWithPath: path)
        let temp: URL = target.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        do {
            try archive.write(to: temp, options: .atomic)
            try FileManager.default.moveItem(at: temp, to: target)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
        // придержанный в documentXml шаг: полоса доходит до конца, когда файл уже на диске.
        // отмена здесь уже ничего не отменяет, а вызывающий счёл бы записанный файл несозданным
        counter.finish()
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
            ZipArchive.Entry(path: "docProps/core.xml", data: Data(coreProps(language: language).utf8)),
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

    /// строки таблицы дописываются в тот же буфер, что и остальной документ:
    /// отдельная строка со всеми репликами держала бы в памяти вторую копию текста
    private static func documentXml(
        subtitle: ImportedSubtitle,
        digest: SubtitleDigest,
        language: AppLanguage,
        roleHighlights: [String: WordHighlightColor],
        voiceSummaries: [VoiceRoleSummary],
        counter: inout ProgressCounter
    ) throws -> String {
        let rolesLine: String = digest.roles.joined(separator: ", ")
        let voiceSummaryXml: String = voiceSummaries.map { summary in
            voiceSummaryParagraph(summary, language: language)
        }.joined()
        var document: String = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body>
                \(paragraph(subtitle.baseName, bold: true, alignment: "center", fontSize: "26", language: language))
                \(paragraph(rolesLine, bold: false, alignment: "", fontSize: "22", language: language))
                \(voiceSummaryXml)
                <w:tbl>
                  <w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="5000" w:type="pct"/></w:tblPr>
                  <w:tblGrid><w:gridCol w:w="1011"/><w:gridCol w:w="1655"/><w:gridCol w:w="7540"/></w:tblGrid>
                  \(headerRow(language: language))

            """

        // один шаг счёта придержан до записи файла: иначе полоса замирает на ста процентах,
        // пока идут сборка архива, сжатие и запись, а отменить этот хвост уже нечем
        for (index, line) in subtitle.lines.enumerated() {
            if index > 0 {
                try counter.step()
            }
            document += tableRow(
                timing: TimeTools.formatClockSeconds(line.start),
                roles: line.displayRoles(language),
                replica: line.text,
                roleHighlights: roleHighlights,
                language: language
            )
        }

        document += """
                </w:tbl>
                \(paragraph("", bold: false, alignment: "", fontSize: "22", language: language))
                \(paragraph(L.text("docx.roleStats", language), bold: true, alignment: "", fontSize: "22", language: language))
                \(roleStatistics(digest: digest, language: language))
                <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="850" w:bottom="1134" w:left="850"/></w:sectPr>
              </w:body>
            </w:document>
            """
        return document
    }

    private static func voiceSummaryParagraph(_ summary: VoiceRoleSummary, language: AppLanguage) -> String {
        let voiceTitle: String = L.format("voice", language, ["n": String(summary.voice.id)])
        let roleList: String = summary.roles.joined(separator: ", ")
        let tail: String = " \(summary.voice.gender.shortTitle(language)) - \(roleList)"
        let titleRun: String = run(voiceTitle, bold: false, fontSize: "22", highlight: summary.voice.color, language: language)
        let tailRun: String = run(tail, bold: false, fontSize: "22", highlight: nil, language: language)
        return "<w:p>\(titleRun)\(tailRun)</w:p>"
    }

    /// строка заголовка помечена tblHeader: иначе на второй странице колонки идут без подписей
    private static func headerRow(language: AppLanguage) -> String {
        """
        <w:tr>
          <w:trPr><w:tblHeader/></w:trPr>
          \(tableCell(L.text("col.timing", language), width: "1011", bold: true, alignment: "center", language: language))
          \(tableCell(L.text("col.role", language), width: "1655", bold: true, alignment: "center", language: language))
          \(tableCell(L.text("col.replica", language), width: "7540", bold: true, alignment: "center", language: language))
        </w:tr>
        """
    }

    /// счётчики уже посчитаны при импорте: считать их здесь заново означало бы держать
    /// две реализации одной величины и однажды разойтись с тем, что показано в окне
    private static func roleStatistics(digest: SubtitleDigest, language: AppLanguage) -> String {
        digest.roles
            .map { role in
                paragraph("\(role) - \(digest.counts[role, default: 0])", bold: false, alignment: "", fontSize: "22", language: language)
            }
            .joined()
    }

    private static func tableRow(
        timing: String,
        roles: [String],
        replica: String,
        roleHighlights: [String: WordHighlightColor],
        language: AppLanguage
    ) -> String {
        """
        <w:tr>
          \(tableCell(timing, width: "1011", bold: false, alignment: "center", language: language))
          \(roleCell(roles, roleHighlights: roleHighlights, language: language))
          \(tableCell(replica, width: "7540", bold: false, alignment: "left", language: language))
        </w:tr>
        """
    }

    /// каждая роль хоровой реплики выделяется своим цветом: одна заливка на всю ячейку
    /// прятала бы то, что вторую роль читает другой голос
    private static func roleCell(_ roles: [String], roleHighlights: [String: WordHighlightColor], language: AppLanguage) -> String {
        let runs: String = roles.enumerated().map { index, role in
            let separator: String = index == 0 ? "" : run(" / ", bold: true, fontSize: "22", highlight: nil, language: language)
            let color: WordHighlightColor? = highlight(for: role, in: roleHighlights)
            return separator + run(role, bold: true, fontSize: "22", highlight: color, language: language)
        }.joined()
        return """
            <w:tc><w:tcPr><w:tcW w:w="1655" w:type="dxa"/><w:vAlign w:val="top"/></w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr>\(runs)</w:p></w:tc>
            """
    }

    private static func tableCell(
        _ value: String,
        width: String,
        bold: Bool,
        alignment: String,
        language: AppLanguage
    ) -> String {
        let content: String = paragraph(value, bold: bold, alignment: alignment, fontSize: "22", language: language)
        return """
            <w:tc><w:tcPr><w:tcW w:w="\(width)" w:type="dxa"/><w:vAlign w:val="top"/></w:tcPr>\(content)</w:tc>
            """
    }

    /// один прогон текста: единица, из которой собираются и абзац, и ячейка с несколькими цветами.
    /// порядок детей w:rPr задан схемой CT_RPr: rFonts, b, sz, highlight, lang
    private static func run(
        _ value: String,
        bold: Bool,
        fontSize: String,
        highlight: WordHighlightColor?,
        language: AppLanguage
    ) -> String {
        let boldXml: String = bold ? "<w:b/>" : ""
        let highlightXml: String = highlight.map { color in #"<w:highlight w:val="\#(color.rawValue)"/>"# } ?? ""
        let langXml: String = #"<w:lang w:val="\#(languageTag(language))"/>"#
        let escapedLines: [String] = value.components(separatedBy: .newlines).map { line in TextTools.xmlEscape(line) }
        let textXml: String = escapedLines.enumerated().map { index, line in
            index == 0 ? #"<w:t xml:space="preserve">\#(line)</w:t>"# : #"<w:br/><w:t xml:space="preserve">\#(line)</w:t>"#
        }.joined()
        let fontsXml: String = #"<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>"#
        let sizeXml: String = #"<w:sz w:val="\#(fontSize)"/>"#
        return "<w:r><w:rPr>\(fontsXml)\(boldXml)\(sizeXml)\(highlightXml)\(langXml)</w:rPr>\(textXml)</w:r>"
    }

    private static func paragraph(_ value: String, bold: Bool, alignment: String, fontSize: String, language: AppLanguage) -> String {
        let paragraphProperties: String = alignment.isEmpty ? "" : #"<w:pPr><w:jc w:val="\#(alignment)"/></w:pPr>"#
        let content: String = run(value, bold: bold, fontSize: fontSize, highlight: nil, language: language)
        return "<w:p>\(paragraphProperties)\(content)</w:p>"
    }

    /// язык текста, а не читателя: без него Word проверяет русские реплики чужим словарём
    private static func languageTag(_ language: AppLanguage) -> String {
        switch language {
        case .ru:
            return "ru-RU"
        case .en:
            return "en-US"
        }
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
        </Types>
        """
    }

    private static func rootRels() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
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

    /// автор документа не заполняется: файл делает пользователь, а не автор программы,
    /// и подписывать его чужим именем в свойствах файла нечестно
    private static func coreProps(language: AppLanguage) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:creator></dc:creator><cp:lastModifiedBy></cp:lastModifiedBy><dc:language>\(languageTag(language))</dc:language></cp:coreProperties>
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
