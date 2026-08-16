import Foundation
import XCTest

@testable import AVT_helper

/// собирает значения прогресса, приходящие из фонового потока
private final class Reported: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    var values: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Double) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

final class CoreTests: XCTestCase {
    private let cp1251: String.Encoding = {
        let raw = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsCyrillic.rawValue))
        return String.Encoding(rawValue: raw)
    }()

    func testTimecodeRoundTrip() throws {
        XCTAssertEqual(try TimeTools.parseSrt("00:01:02,500"), 62.5, accuracy: 0.0001)
        XCTAssertEqual(TimeTools.formatSrt(62.5), "00:01:02,500")
        XCTAssertEqual(try TimeTools.parseAss("0:01:02.50"), 62.5, accuracy: 0.0001)
        XCTAssertEqual(TimeTools.formatAss(62.5), "0:01:02.50")
        XCTAssertEqual(try TimeTools.parseVtt("01:02.500"), 62.5, accuracy: 0.0001)
        XCTAssertEqual(TimeTools.formatVtt(62.5), "00:01:02.500")
    }

    func testParseRejectsGarbage() {
        XCTAssertThrowsError(try TimeTools.parseSrt("nope"))
    }

    func testFractionDigitsAndDotTolerance() throws {
        XCTAssertEqual(try TimeTools.parseSrt("00:00:01,5"), 1.5, accuracy: 0.0001)
        XCTAssertEqual(try TimeTools.parseSrt("00:00:01,50"), 1.5, accuracy: 0.0001)
        XCTAssertEqual(try TimeTools.parseSrt("00:00:01,500"), 1.5, accuracy: 0.0001)
        XCTAssertEqual(try TimeTools.parseSrt("00:00:01.500"), 1.5, accuracy: 0.0001)
    }

    func testAssImport() throws {
        let body = """
            [Events]
            Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
            Dialogue: 0,0:00:01.00,0:00:02.00,Default,Анна,0,0,0,,{\\i1}Привет,\\Nмир
            """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("avt_\(UUID().uuidString).ass")
        try body.data(using: .utf8)?.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let imported = try SubtitleImporter.importFile(path: url.path, language: .ru)
        XCTAssertEqual(imported.lines.count, 1)
        XCTAssertEqual(imported.lines.first?.roles.first, "Анна")
        XCTAssertEqual(imported.lines.first?.text, "Привет,\nмир")
        XCTAssertEqual(imported.lines.first?.start ?? 0, 1, accuracy: 0.0001)
    }

    func testVttImport() throws {
        let body = """
            WEBVTT

            1
            00:01.000 --> 00:02.000 align:start
            [Анна] Привет
            """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("avt_\(UUID().uuidString).vtt")
        try body.data(using: .utf8)?.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let imported = try SubtitleImporter.importFile(path: url.path, language: .ru)
        XCTAssertEqual(imported.lines.count, 1)
        XCTAssertEqual(imported.lines.first?.text, "Привет")
        XCTAssertTrue(imported.allRoles(.ru).contains("Анна"))
    }

    func testVttVoiceTagBecomesRole() throws {
        let body = """
            WEBVTT

            1
            00:00:01.000 --> 00:00:02.000
            <v Анна>Привет, <i>мир</i> &amp; все

            2
            00:00:03.000 --> 00:00:04.000
            <v.loud Борис>Пока
            """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("avt_\(UUID().uuidString).vtt")
        try Data(body.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let imported = try SubtitleImporter.importFile(path: url.path, language: .ru)

        XCTAssertEqual(imported.allRoles(.ru), ["Анна", "Борис"])
        XCTAssertEqual(imported.lines.first?.text, "Привет, мир & все")
    }

    func testAssignRolesRespectsGenderAndLoad() throws {
        let lines: [SubtitleLine] = [
            ("Hero", 6), ("Sidekick", 2), ("Queen", 3),
        ].flatMap { role, count in
            (0..<count).map { index in
                SubtitleLine(
                    id: UUID(), start: TimeInterval(index), end: TimeInterval(index) + 1,
                    roles: [role], text: "line", style: "", effect: "", sex: .unknown
                )
            }
        }
        let subtitle = ImportedSubtitle(baseName: "cast", sourcePath: "", sourceType: .srt, lines: lines)
        let voices: [VoiceConfig] = [
            VoiceConfig(id: 1, gender: .male, color: .yellow),
            VoiceConfig(id: 2, gender: .male, color: .green),
            VoiceConfig(id: 3, gender: .female, color: .cyan),
        ]
        let settings: [RoleGenderSetting] = [
            RoleGenderSetting(role: "Hero", gender: .male),
            RoleGenderSetting(role: "Sidekick", gender: .male),
            RoleGenderSetting(role: "Queen", gender: .female),
        ]

        let digest = SubtitleDigest(subtitle: subtitle, language: .ru)
        let result = try RoleAssignmentService.assignRoles(counts: digest.counts, voices: voices, roleSettings: settings, language: .ru)
        XCTAssertEqual(result.roleToVoice["Queen"], 3)
        XCTAssertEqual(result.roleToVoice["Hero"], 1)
        XCTAssertEqual(result.roleToVoice["Sidekick"], 2)
        XCTAssertEqual(result.roleToHighlight["Queen"], .cyan)
    }

    func testExportDoesNotOverwriteSourceFile() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sourceUrl = dir.appendingPathComponent("movie.ass")
        let body = """
            [Events]
            Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
            Dialogue: 0,0:00:01.00,0:00:02.00,Default,Анна,0,0,0,,Привет
            """
        try body.data(using: .utf8)?.write(to: sourceUrl)
        let originalData = try Data(contentsOf: sourceUrl)

        let imported = try SubtitleImporter.importFile(path: sourceUrl.path, language: .ru)
        var paths = OutputPathAllocator(sourcePath: imported.sourcePath)
        let created = try SubtitleExporter.exportAss(subtitle: imported, outputFolder: dir.path, language: .ru, paths: &paths)

        XCTAssertEqual(URL(fileURLWithPath: created).lastPathComponent, "movie (1).ass")
        XCTAssertEqual(try Data(contentsOf: sourceUrl), originalData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: created))
    }

    func testDocxStaysValidXmlWithControlCharacters() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subtitle = ImportedSubtitle(
            baseName: "control",
            sourcePath: "",
            sourceType: .srt,
            lines: [
                SubtitleLine(
                    id: UUID(), start: 1, end: 2, roles: ["Анна"],
                    text: "Привет\u{0B}мир\u{01}", style: "", effect: "", sex: .unknown
                )
            ]
        )
        var paths = OutputPathAllocator(sourcePath: subtitle.sourcePath)
        let path = try DocxExporter.export(
            subtitle: subtitle, outputFolder: dir.path, digest: SubtitleDigest(subtitle: subtitle, language: .ru),
            language: .ru, paths: &paths)

        let document = try run("/usr/bin/unzip", ["-p", path, "word/document.xml"])
        let xmlPath = dir.appendingPathComponent("document.xml")
        try document.write(to: xmlPath)
        let lint = Process()
        lint.executableURL = URL(fileURLWithPath: "/usr/bin/xmllint")
        lint.arguments = ["--noout", xmlPath.path]
        lint.standardOutput = Pipe()
        lint.standardError = Pipe()
        try lint.run()
        lint.waitUntilExit()

        XCTAssertEqual(lint.terminationStatus, 0, "document.xml не проходит строгую проверку XML")
    }

    func testSeparateRoleFilesDoNotCollide() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subtitle = ImportedSubtitle(
            baseName: "coll",
            sourcePath: "",
            sourceType: .srt,
            lines: [
                SubtitleLine(id: UUID(), start: 1, end: 2, roles: ["A:B"], text: "one", style: "", effect: "", sex: .unknown),
                SubtitleLine(id: UUID(), start: 3, end: 4, roles: ["A*B"], text: "two", style: "", effect: "", sex: .unknown),
            ]
        )
        let settings = ExportSettings(
            exportAss: false, exportSrt: true, exportVtt: false, exportDocx: false,
            srtFullWithRoles: false, srtSeparateFiles: true, srtSeparateWithRoles: false, selectedRoles: ["A:B", "A*B"], roleHighlights: [:]
        )

        let created = try SubtitleExporter.export(
            subtitle: subtitle, outputFolder: dir.path, settings: settings, digest: SubtitleDigest(subtitle: subtitle, language: .ru),
            language: .ru)

        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(Set(created).count, 2)
        let texts = try created.map { path in try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) }
        XCTAssertTrue(texts.contains { text in text.contains("one") })
        XCTAssertTrue(texts.contains { text in text.contains("two") })
    }

    func testSecondExportKeepsEarlierFiles() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subtitle = makeSubtitle()
        let settings = ExportSettings(
            exportAss: false, exportSrt: true, exportVtt: false, exportDocx: false,
            srtFullWithRoles: false, srtSeparateFiles: false, srtSeparateWithRoles: false, selectedRoles: [], roleHighlights: [:]
        )

        let first = try SubtitleExporter.export(
            subtitle: subtitle, outputFolder: dir.path, settings: settings, digest: SubtitleDigest(subtitle: subtitle, language: .ru),
            language: .ru)
        let second = try SubtitleExporter.export(
            subtitle: subtitle, outputFolder: dir.path, settings: settings, digest: SubtitleDigest(subtitle: subtitle, language: .ru),
            language: .ru)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(URL(fileURLWithPath: try XCTUnwrap(second.first)).lastPathComponent, "sample [FULL] (1).srt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(first.first)))
    }

    func testAssRoundTripKeepsCurlyBraces() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subtitle = ImportedSubtitle(
            baseName: "braces",
            sourcePath: "",
            sourceType: .ass,
            lines: [
                SubtitleLine(
                    id: UUID(), start: 1, end: 2, roles: ["Анна"], text: "текст {в скобках} тут", style: "", effect: "", sex: .unknown)
            ]
        )
        var paths = OutputPathAllocator(sourcePath: subtitle.sourcePath)

        let created = try SubtitleExporter.exportAss(subtitle: subtitle, outputFolder: dir.path, language: .ru, paths: &paths)
        let reimported = try SubtitleImporter.importFile(path: created, language: .ru)

        XCTAssertEqual(reimported.lines.first?.text, "текст {в скобках} тут")
    }

    func testExportReportsProgressAndStopsWhenCancelled() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lines = (0..<500).map { index in
            SubtitleLine(
                id: UUID(), start: TimeInterval(index), end: TimeInterval(index) + 1,
                roles: ["Анна"], text: "строка \(index)", style: "", effect: "", sex: .unknown
            )
        }
        let subtitle = ImportedSubtitle(baseName: "progress", sourcePath: "", sourceType: .srt, lines: lines)
        let settings = ExportSettings(
            exportAss: true, exportSrt: true, exportVtt: true, exportDocx: true,
            srtFullWithRoles: false, srtSeparateFiles: false, srtSeparateWithRoles: false, selectedRoles: [], roleHighlights: [:]
        )

        let reported = Reported()
        _ = try SubtitleExporter.export(
            subtitle: subtitle, outputFolder: dir.path, settings: settings, digest: SubtitleDigest(subtitle: subtitle, language: .ru),
            language: .ru
        ) { fraction in
            reported.append(fraction)
        }
        let values = reported.values
        XCTAssertFalse(values.isEmpty)
        XCTAssertEqual(values.last ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertEqual(values, values.sorted())

        let cancelledDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: cancelledDir) }
        let work = Task.detached {
            try SubtitleExporter.export(
                subtitle: subtitle, outputFolder: cancelledDir.path, settings: settings,
                digest: SubtitleDigest(subtitle: subtitle, language: .ru), language: .ru)
        }
        work.cancel()
        do {
            _ = try await work.value
            XCTFail("отменённый экспорт завершился успешно")
        } catch is CancellationError {
            // отмена дошла до цикла записи
        }
    }

    func testSrpImportReadsRolesAndGender() throws {
        let body = """
            <?xml version="1.0" encoding="utf-8"?>
            <Root>
              <DocumentElement>
                <Character>Анна</Character>
                <Sex>Ж</Sex>
                <BeginTime>00:00:01,000</BeginTime>
                <EndTime>00:00:02,000</EndTime>
                <Text>Привет\\Nмир</Text>
              </DocumentElement>
              <DocumentElement>
                <Character></Character>
                <Sex></Sex>
                <BeginTime>00:00:03.000</BeginTime>
                <EndTime>00:00:04.000</EndTime>
                <Text>Без роли</Text>
              </DocumentElement>
            </Root>
            """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("avt_\(UUID().uuidString).srp")
        try body.data(using: .utf8)?.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let imported = try SubtitleImporter.importFile(path: url.path, language: .ru)

        XCTAssertEqual(imported.lines.count, 2)
        XCTAssertEqual(imported.lines.first?.roles, ["Анна"])
        XCTAssertEqual(imported.lines.first?.sex, .female)
        XCTAssertEqual(imported.lines.first?.text, "Привет мир")
        XCTAssertEqual(imported.lines.last?.roles, [])
        XCTAssertEqual(imported.lines.last?.displayRoles(.ru), ["Не назначено"])
        XCTAssertEqual(imported.lines.last?.displayRoles(.en), ["Unassigned"])
        XCTAssertEqual(imported.lines.last?.start ?? 0, 3, accuracy: 0.0001)
    }

    func testAssKeepsEveryRoleOfAChorusLine() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subtitle = ImportedSubtitle(
            baseName: "chorus",
            sourcePath: "",
            sourceType: .srt,
            lines: [
                SubtitleLine(id: UUID(), start: 1, end: 2, roles: ["Анна", "Борис"], text: "хором", style: "", effect: "", sex: .unknown)
            ]
        )
        var paths = OutputPathAllocator(sourcePath: "")

        let created = try SubtitleExporter.exportAss(subtitle: subtitle, outputFolder: dir.path, language: .ru, paths: &paths)
        let reimported = try SubtitleImporter.importFile(path: created, language: .ru)

        XCTAssertEqual(reimported.lines.first?.roles, ["Анна", "Борис"])
    }

    func testRoleSpellingIsCanonicalizedAcrossFile() throws {
        let body = """
            1
            00:00:01,000 --> 00:00:02,000
            [Анна] раз

            2
            00:00:03,000 --> 00:00:04,000
            [АННА] два

            3
            00:00:05,000 --> 00:00:06,000
            [анна] три
            """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("avt_\(UUID().uuidString).srt")
        try Data(body.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let imported = try SubtitleImporter.importFile(path: url.path, language: .ru)

        XCTAssertEqual(imported.allRoles(.ru), ["Анна"])
        XCTAssertEqual(SubtitleDigest(subtitle: imported, language: .ru).counts, ["Анна": 3])
    }

    func testSrpRejectsExternalEntities() throws {
        let secret = FileManager.default.temporaryDirectory.appendingPathComponent("avt_secret_\(UUID().uuidString).txt")
        try Data("СЕКРЕТ".utf8).write(to: secret)
        defer { try? FileManager.default.removeItem(at: secret) }
        let body = """
            <?xml version="1.0" encoding="utf-8"?>
            <!DOCTYPE Root [ <!ENTITY leak SYSTEM "file://\(secret.path)"> ]>
            <Root>
              <DocumentElement>
                <Character>&leak;</Character>
                <Sex>М</Sex>
                <BeginTime>00:00:01,000</BeginTime>
                <EndTime>00:00:02,000</EndTime>
                <Text>текст</Text>
              </DocumentElement>
            </Root>
            """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("avt_\(UUID().uuidString).srp")
        try Data(body.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try SubtitleImporter.importFile(path: url.path, language: .ru)) { error in
            XCTAssertFalse(L.describe(error, .ru).contains("СЕКРЕТ"))
            XCTAssertTrue(L.describe(error, .ru).contains("DTD"))
        }
    }

    func testImportRejectsFileWithoutLines() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("avt_\(UUID().uuidString).srt")
        try Data("не субтитры, просто текст\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try SubtitleImporter.importFile(path: url.path, language: .ru)) { error in
            XCTAssertTrue(L.describe(error, .ru).contains("ни одной реплики"))
        }
    }

    func testDocxContainsTableRolesAndStatistics() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subtitle = ImportedSubtitle(
            baseName: "doc",
            sourcePath: "",
            sourceType: .srt,
            lines: [
                SubtitleLine(id: UUID(), start: 1, end: 2, roles: ["Анна"], text: "Первая", style: "", effect: "", sex: .unknown),
                SubtitleLine(id: UUID(), start: 3, end: 4, roles: [], text: "Вторая", style: "", effect: "", sex: .unknown),
            ]
        )
        var paths = OutputPathAllocator(sourcePath: subtitle.sourcePath)
        let path = try DocxExporter.export(
            subtitle: subtitle,
            outputFolder: dir.path,
            digest: SubtitleDigest(subtitle: subtitle, language: .ru),
            language: .ru,
            paths: &paths,
            roleHighlights: ["Анна": .cyan]
        )

        let xml = try XCTUnwrap(String(data: try run("/usr/bin/unzip", ["-p", path, "word/document.xml"]), encoding: .utf8))
        XCTAssertTrue(xml.contains("Тайминг"))
        XCTAssertTrue(xml.contains("Первая"))
        XCTAssertTrue(xml.contains("Не назначено"))
        XCTAssertTrue(xml.contains(#"<w:highlight w:val="cyan"/>"#))
        XCTAssertTrue(xml.contains("Статистика по ролям"))
        XCTAssertTrue(xml.contains("Анна - 1"))
    }

    func testVersionComparison() {
        XCTAssertEqual(UpdateChecker.normalizeTag("v.1.6.5"), "1.6.5")
        XCTAssertEqual(UpdateChecker.normalizeTag("v1.6.5"), "1.6.5")
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.6.5", than: "0.0.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.7", than: "1.6.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.6.5", than: "1.6.5"))
        XCTAssertFalse(UpdateChecker.isNewer("1.6.4", than: "1.6.5"))
        XCTAssertFalse(UpdateChecker.isNewer("1.6.5", than: "1.6.6"))
    }

    func testTextTools() {
        XCTAssertEqual(TextTools.cleanRoleName("   "), "")
        XCTAssertEqual(TextTools.cleanRoleName("Anna / Bob"), "Anna_Bob")
        XCTAssertEqual(TextTools.extractBracketRoles("[Anna][Bob] hi"), ["Anna", "Bob"])
        XCTAssertEqual(TextTools.extractBracketRoles("[Anna] hi [loudly]"), ["Anna"])
        XCTAssertEqual(TextTools.extractBracketRoles("Он крикнул [громко] и ушёл"), [])
        XCTAssertEqual(TextTools.extractBracketRoles("[Anna] раз\n[Bob] два"), ["Anna", "Bob"])
        XCTAssertEqual(TextTools.safeFileName("a/b:c"), "a_b_c")
        XCTAssertEqual(TextTools.xmlEscape("a<b>&\"'"), "a&lt;b&gt;&amp;&quot;&apos;")
    }

    func testImportWindows1251Srt() throws {
        let body = "1\n00:00:01,000 --> 00:00:02,000\n[Анна] Привет\n"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("avt_\(UUID().uuidString).srt")
        try XCTUnwrap(body.data(using: cp1251)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let imported = try SubtitleImporter.importFile(path: url.path, language: .ru)
        XCTAssertEqual(imported.lines.count, 1)
        XCTAssertEqual(imported.lines.first?.text, "Привет")
        XCTAssertTrue(imported.allRoles(.ru).contains("Анна"))
    }

    func testSrtExportRoundTrip() throws {
        let subtitle = makeSubtitle()
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let settings = ExportSettings(
            exportAss: false,
            exportSrt: true,
            exportVtt: false,
            exportDocx: false,
            srtFullWithRoles: false,
            srtSeparateFiles: false,
            srtSeparateWithRoles: false,
            selectedRoles: [],
            roleHighlights: [:]
        )
        let created = try SubtitleExporter.export(
            subtitle: subtitle, outputFolder: dir.path, settings: settings, digest: SubtitleDigest(subtitle: subtitle, language: .ru),
            language: .ru)
        let content = try String(contentsOf: URL(fileURLWithPath: try XCTUnwrap(created.first)), encoding: .utf8)
        XCTAssertTrue(content.contains("00:00:01,000 --> 00:00:02,000"))
        XCTAssertTrue(content.contains("Привет"))
    }

    func testDocxExportProducesValidZip() throws {
        let subtitle = makeSubtitle()
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var paths = OutputPathAllocator(sourcePath: subtitle.sourcePath)
        let path = try DocxExporter.export(
            subtitle: subtitle, outputFolder: dir.path, digest: SubtitleDigest(subtitle: subtitle, language: .ru),
            language: .ru, paths: &paths)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-t", path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    /// заголовок исходного ASS обязан пережить круг: без него стиль строки Dialogue
    /// ссылается в пустоту, и плеер молча подменяет его на Default
    func testAssExportKeepsSourceStyles() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let body = """
            [Script Info]
            ScriptType: v4.00+
            PlayResX: 1280
            PlayResY: 720

            [V4+ Styles]
            Format: Name, Fontname, Fontsize, PrimaryColour, Alignment
            Style: Default,Arial,48,&H00FFFFFF,2
            Style: Signs,Impact,60,&H0000FFFF,8

            [Events]
            Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
            Dialogue: 0,0:00:01.00,0:00:02.00,Signs,Анна,0,0,0,,Вывеска
            """
        let source = dir.appendingPathComponent("styled.ass")
        try Data(body.utf8).write(to: source)

        let imported = try SubtitleImporter.importFile(path: source.path, language: .ru)
        var paths = OutputPathAllocator(sourcePath: imported.sourcePath)
        let created = try SubtitleExporter.exportAss(subtitle: imported, outputFolder: dir.path, language: .ru, paths: &paths)
        let text = try String(contentsOf: URL(fileURLWithPath: created), encoding: .utf8)

        XCTAssertTrue(text.contains("Style: Signs,Impact,60"))
        XCTAssertTrue(text.contains("PlayResX: 1280"))
        XCTAssertTrue(text.contains(",Signs,Анна,"))
    }

    /// стиль, которого нет в заголовке, заменяется на Default: ссылка в пустоту хуже честной подмены
    func testAssExportFallsBackToDeclaredStyle() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subtitle = ImportedSubtitle(
            baseName: "orphan",
            sourcePath: "",
            sourceType: .ass,
            lines: [
                SubtitleLine(id: UUID(), start: 1, end: 2, roles: ["Анна"], text: "текст", style: "Missing", effect: "", sex: .unknown)
            ]
        )
        var paths = OutputPathAllocator(sourcePath: "")

        let created = try SubtitleExporter.exportAss(subtitle: subtitle, outputFolder: dir.path, language: .ru, paths: &paths)
        let text = try String(contentsOf: URL(fileURLWithPath: created), encoding: .utf8)

        XCTAssertFalse(text.contains("Missing"))
        XCTAssertTrue(text.contains(",Default,Анна,"))
    }

    /// формат разрешает свой порядок полей, и он объявлен строкой Format
    func testAssHonoursDeclaredFieldOrder() throws {
        let body = """
            [Events]
            Format: Start, End, Style, Name, Layer, MarginL, MarginR, MarginV, Effect, Text
            Dialogue: 0:00:05.00,0:00:06.00,Default,Борис,0,0,0,0,,Привет
            """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("avt_\(UUID().uuidString).ass")
        try Data(body.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let imported = try SubtitleImporter.importFile(path: url.path, language: .ru)

        XCTAssertEqual(imported.lines.first?.roles, ["Борис"])
        XCTAssertEqual(imported.lines.first?.text, "Привет")
        XCTAssertEqual(imported.lines.first?.start ?? 0, 5, accuracy: 0.0001)
    }

    /// нулевой байт - допустимый символ UTF-8, поэтому UTF-16 без BOM проходил проверку
    /// и превращался в текст в дырках
    func testImportsUtf16WithoutBom() throws {
        let body = "1\n00:00:01,000 --> 00:00:02,000\n[Анна] Привет\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("avt_\(UUID().uuidString).srt")
        try XCTUnwrap(body.data(using: .utf16LittleEndian)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let imported = try SubtitleImporter.importFile(path: url.path, language: .ru)

        XCTAssertEqual(imported.lines.count, 1)
        XCTAssertEqual(imported.lines.first?.text, "Привет")
        XCTAssertTrue(imported.allRoles(.ru).contains("Анна"))
    }

    func testRejectsUndecodableFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("avt_\(UUID().uuidString).srt")
        try Data((0..<512).map { index in UInt8((index * 7 + 1) % 32) }).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try SubtitleImporter.importFile(path: url.path, language: .ru)) { error in
            XCTAssertTrue(L.describe(error, .ru).contains("кодировку"))
        }
    }

    /// имя файла длиннее предела файловой системы роняло запись посреди прогона
    func testLongRoleNameStillWrites() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let longRole = String(repeating: "Длинноеимя", count: 40)
        let subtitle = ImportedSubtitle(
            baseName: "long",
            sourcePath: "",
            sourceType: .srt,
            lines: [
                SubtitleLine(id: UUID(), start: 1, end: 2, roles: [longRole], text: "текст", style: "", effect: "", sex: .unknown)
            ]
        )
        let settings = ExportSettings(
            exportAss: false, exportSrt: true, exportVtt: false, exportDocx: false,
            srtFullWithRoles: false, srtSeparateFiles: true, srtSeparateWithRoles: false, selectedRoles: [longRole], roleHighlights: [:]
        )

        let created = try SubtitleExporter.export(
            subtitle: subtitle, outputFolder: dir.path, settings: settings,
            digest: SubtitleDigest(subtitle: subtitle, language: .ru), language: .ru)

        let name = try XCTUnwrap(created.first.map { path in URL(fileURLWithPath: path).lastPathComponent })
        XCTAssertLessThanOrEqual(name.utf8.count, 255)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(created.first)))
    }

    /// у хоровой реплики каждая роль своего цвета: одна заливка на ячейку прятала бы второй голос
    func testChorusLineKeepsColorOfEveryRole() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subtitle = ImportedSubtitle(
            baseName: "chorus",
            sourcePath: "",
            sourceType: .srt,
            lines: [
                SubtitleLine(id: UUID(), start: 1, end: 2, roles: ["Анна", "Борис"], text: "хором", style: "", effect: "", sex: .unknown)
            ]
        )
        var paths = OutputPathAllocator(sourcePath: "")
        let path = try DocxExporter.export(
            subtitle: subtitle,
            outputFolder: dir.path,
            digest: SubtitleDigest(subtitle: subtitle, language: .ru),
            language: .ru,
            paths: &paths,
            roleHighlights: ["Анна": .cyan, "Борис": .magenta]
        )

        let xml = try XCTUnwrap(String(data: try run("/usr/bin/unzip", ["-p", path, "word/document.xml"]), encoding: .utf8))
        XCTAssertTrue(xml.contains(#"<w:highlight w:val="cyan"/>"#))
        XCTAssertTrue(xml.contains(#"<w:highlight w:val="magenta"/>"#))
    }

    /// цвет роли из окна доходит до обычного DOCX, а не только до разролёвки:
    /// иначе экран и документ показывают разное
    func testPlainDocxCarriesRoleColors() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subtitle = makeSubtitle()
        let settings = ExportSettings(
            exportAss: false, exportSrt: false, exportVtt: false, exportDocx: true,
            srtFullWithRoles: false, srtSeparateFiles: false, srtSeparateWithRoles: false,
            selectedRoles: [], roleHighlights: ["Анна": .green]
        )

        let created = try SubtitleExporter.export(
            subtitle: subtitle, outputFolder: dir.path, settings: settings,
            digest: SubtitleDigest(subtitle: subtitle, language: .ru), language: .ru)

        let xml = try XCTUnwrap(
            String(data: try run("/usr/bin/unzip", ["-p", try XCTUnwrap(created.first), "word/document.xml"]), encoding: .utf8))
        XCTAssertTrue(xml.contains(#"<w:highlight w:val="green"/>"#))
    }

    /// голосов не может быть больше, чем цветов выделения, и состав переживает закрытие листа
    @MainActor
    func testVoiceSetupCapsAtColorCountAndPersists() throws {
        let name = "avt.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let setup = VoiceSetup(defaults: defaults)
        setup.resize(to: 99)
        XCTAssertEqual(setup.voices.count, WordHighlightColor.allCases.count)
        XCTAssertEqual(Set(setup.voices.map { voice in voice.color }).count, setup.voices.count)

        setup.resize(to: 3)
        let colors = setup.voices.map { voice in voice.color }
        XCTAssertEqual(VoiceSetup(defaults: defaults).voices.map { voice in voice.color }, colors)
    }

    /// прерванный экспорт обязан назвать то, что уже лежит на диске
    func testPartialExportNamesWhatWasWritten() {
        let error = PartialExportError(
            created: ["/tmp/a.srt", "/tmp/b.srt"],
            cause: SubtitleError.exportFailed("диск полон")
        )
        let message = L.describe(error, .ru)

        XCTAssertTrue(message.contains("диск полон"))
        XCTAssertTrue(message.contains("2 файла"))
    }

    private func makeSubtitle() -> ImportedSubtitle {
        ImportedSubtitle(
            baseName: "sample",
            sourcePath: "",
            sourceType: .srt,
            lines: [
                SubtitleLine(
                    id: UUID(), start: 1, end: 2, roles: ["Анна"],
                    text: "Привет", style: "", effect: "", sex: .unknown
                )
            ]
        )
    }

    /// запускает утилиту и отдаёт её stdout
    private func run(_ tool: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return output
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
