import Foundation
import XCTest

@testable import AVT_helper

/// ключи локализации - строки, поэтому опечатку в них ловит не компилятор, а этот тест
final class LocalizationTests: XCTestCase {
    private func table(_ language: AppLanguage) throws -> [String: String] {
        let bundle: Bundle = L.bundle(language)
        let url: URL = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings"))
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }

    /// каталог исходников приложения, найденный от файла теста
    private var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AVT_helper")
    }

    func testBothLanguagesCarryTheSameKeys() throws {
        let ru: [String: String] = try table(.ru)
        let en: [String: String] = try table(.en)

        XCTAssertFalse(ru.isEmpty)
        XCTAssertEqual(Set(ru.keys), Set(en.keys))
        XCTAssertTrue(ru.values.allSatisfy { value in !value.isEmpty })
        XCTAssertTrue(en.values.allSatisfy { value in !value.isEmpty })
    }

    /// язык выбирается в программе, а не системой: каждый должен приходить из своего бандла
    func testLanguageSelectsItsOwnBundle() {
        XCTAssertEqual(L.text("start", .ru), "Начать")
        XCTAssertEqual(L.text("start", .en), "Start")
        XCTAssertEqual(L.format("update.available", .en, ["v": "1.7.0"]), "Version 1.7.0 is available.")
    }

    func testEveryKeyUsedInCodeExists() throws {
        let known: Set<String> = Set(try table(.ru).keys)
        // граница перед t обязательна, иначе под шаблон попадают Text( и keyboardShortcut(
        let pattern = try NSRegularExpression(pattern: #"(?:L\.text|L\.format|(?<![\w.])t)\(\s*"([\w.]+)""#)
        let files: [URL] = try FileManager.default
            .contentsOfDirectory(at: sourcesDirectory, includingPropertiesForKeys: nil)
            .filter { url in url.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "исходники приложения не найдены рядом с тестами")

        var used: Set<String> = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in pattern.matches(in: text, range: range) {
                if let keyRange = Range(match.range(at: 1), in: text) {
                    used.insert(String(text[keyRange]))
                }
            }
        }

        // ключи из таблиц вида [("qa.q1", "qa.a1")] регулярка не видит, поэтому проверка односторонняя
        XCTAssertTrue(used.subtracting(known).isEmpty, "нет перевода для ключей: \(used.subtracting(known).sorted())")
    }
}
