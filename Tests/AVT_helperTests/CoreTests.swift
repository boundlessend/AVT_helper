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
