import Foundation
import XCTest

@testable import AVT_helper

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

        let imported = try SubtitleImporter.importFile(path: url.path)
        XCTAssertEqual(imported.lines.count, 1)
        XCTAssertEqual(imported.lines.first?.role, "Анна")
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

        let imported = try SubtitleImporter.importFile(path: url.path)
        XCTAssertEqual(imported.lines.count, 1)
        XCTAssertEqual(imported.lines.first?.text, "Привет")
        XCTAssertTrue(imported.allRoles.contains("Анна"))
    }

    func testAssignRolesRespectsGenderAndLoad() throws {
        let lines: [SubtitleLine] = [
            ("Hero", 6), ("Sidekick", 2), ("Queen", 3),
        ].flatMap { role, count in
            (0..<count).map { index in
                SubtitleLine(
                    id: UUID(), start: TimeInterval(index), end: TimeInterval(index) + 1,
                    role: role, roles: [role], text: "line", style: "", effect: "", sex: ""
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

        let result = try RoleAssignmentService.assignRoles(subtitle: subtitle, voices: voices, roleSettings: settings)
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

        let imported = try SubtitleImporter.importFile(path: sourceUrl.path)
        let created = try SubtitleExporter.exportAss(subtitle: imported, outputFolder: dir.path)

        XCTAssertEqual(URL(fileURLWithPath: created).lastPathComponent, "movie (1).ass")
        XCTAssertEqual(try Data(contentsOf: sourceUrl), originalData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: created))
    }

    func testTextTools() {
        XCTAssertEqual(TextTools.cleanRoleName("   "), Roles.unassigned)
        XCTAssertEqual(TextTools.cleanRoleName("Anna / Bob"), "Anna_Bob")
        XCTAssertEqual(TextTools.extractBracketRoles("[Anna] hi [Bob]"), ["Anna", "Bob"])
        XCTAssertEqual(TextTools.safeFileName("a/b:c"), "a_b_c")
        XCTAssertEqual(TextTools.xmlEscape("a<b>&\"'"), "a&lt;b&gt;&amp;&quot;&apos;")
    }

    func testImportWindows1251Srt() throws {
        let body = "1\n00:00:01,000 --> 00:00:02,000\n[Анна] Привет\n"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("avt_\(UUID().uuidString).srt")
        try XCTUnwrap(body.data(using: cp1251)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let imported = try SubtitleImporter.importFile(path: url.path)
        XCTAssertEqual(imported.lines.count, 1)
        XCTAssertEqual(imported.lines.first?.text, "Привет")
        XCTAssertTrue(imported.allRoles.contains("Анна"))
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
            selectedRoles: []
        )
        let created = try SubtitleExporter.export(subtitle: subtitle, outputFolder: dir.path, settings: settings)
        let content = try String(contentsOf: URL(fileURLWithPath: try XCTUnwrap(created.first)), encoding: .utf8)
        XCTAssertTrue(content.contains("00:00:01,000 --> 00:00:02,000"))
        XCTAssertTrue(content.contains("Привет"))
    }

    func testDocxExportProducesValidZip() throws {
        let subtitle = makeSubtitle()
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try DocxExporter.export(subtitle: subtitle, outputFolder: dir.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-t", path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func makeSubtitle() -> ImportedSubtitle {
        ImportedSubtitle(
            baseName: "sample",
            sourcePath: "",
            sourceType: .srt,
            lines: [
                SubtitleLine(
                    id: UUID(), start: 1, end: 2, role: "Анна", roles: ["Анна"],
                    text: "Привет", style: "", effect: "", sex: ""
                )
            ]
        )
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
