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

    /// имена плейсхолдеров {token} в строке перевода
    private func placeholders(_ value: String) throws -> Set<String> {
        let pattern: NSRegularExpression = try NSRegularExpression(pattern: #"\{([^{}]*)\}"#)
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return Set(
            pattern.matches(in: value, range: range).compactMap { match in
                Range(match.range(at: 1), in: value).map { range in String(value[range]) }
            })
    }

    /// L.format подставляет значения по имени токена, поэтому потерянный при переводе {token}
    /// доходит до пользователя как «{v}» в тексте, а лишний остаётся в строке навсегда
    func testBothLanguagesUseTheSamePlaceholders() throws {
        let ru: [String: String] = try table(.ru)
        let en: [String: String] = try table(.en)

        for key in ru.keys.sorted() {
            let source: Set<String> = try placeholders(XCTUnwrap(ru[key]))
            let translation: Set<String> = try placeholders(XCTUnwrap(en[key]))
            XCTAssertEqual(source, translation, "разные плейсхолдеры у ключа \(key)")
        }
    }

    /// русский требует трёх форм, и правило для 11-14 не совпадает с правилом для 1-4.
    /// формы приходят из .stringsdict, а он читается только через бандл нужного языка
    func testPluralFormsFollowTheLanguageRules() {
        XCTAssertEqual(L.plural("count.lines", .ru, 1), "1 реплика")
        XCTAssertEqual(L.plural("count.lines", .ru, 2), "2 реплики")
        XCTAssertEqual(L.plural("count.lines", .ru, 5), "5 реплик")
        XCTAssertEqual(L.plural("count.lines", .ru, 11), "11 реплик")
        XCTAssertEqual(L.plural("count.lines", .ru, 21), "21 реплика")
        XCTAssertEqual(L.plural("count.roles", .ru, 3), "3 роли")
        XCTAssertEqual(L.plural("count.files", .ru, 0), "0 файлов")
        XCTAssertEqual(L.plural("count.lines", .en, 1), "1 line")
        XCTAssertEqual(L.plural("count.lines", .en, 2), "2 lines")
    }

    /// в обоих языках объявлены одни и те же формы множественного числа
    func testBothLanguagesCarryTheSamePluralKeys() throws {
        let ru: Set<String> = try Set(pluralTable(.ru).keys)
        let en: Set<String> = try Set(pluralTable(.en).keys)

        XCTAssertFalse(ru.isEmpty)
        XCTAssertEqual(ru, en)
    }

    private func pluralTable(_ language: AppLanguage) throws -> [String: Any] {
        let bundle: Bundle = L.bundle(language)
        let url: URL = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "stringsdict"))
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: Any])
    }

    /// выбор языка обязан дойти до AppleLanguages: меню и системные панели читают только его.
    /// проверяется домен программы, а не итоговое значение: без своего ключа UserDefaults
    /// отдаёт общесистемный список, и «как в системе» именно так и выглядит
    @MainActor
    func testLanguagePreferenceWritesAppleLanguages() throws {
        let name: String = "avt.test.\(UUID().uuidString)"
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        // свежая установка на «как в системе» перезапуска не требует
        XCTAssertFalse(LanguagePreference.system.needsRelaunch(defaults))
        XCTAssertTrue(LanguagePreference.en.needsRelaunch(defaults))

        LanguagePreference.en.apply(defaults)
        XCTAssertEqual(
            defaults.persistentDomain(forName: name)?[LanguagePreference.appleLanguagesKey] as? [String],
            ["en"]
        )
        XCTAssertFalse(LanguagePreference.en.needsRelaunch(defaults))
        XCTAssertTrue(LanguagePreference.system.needsRelaunch(defaults))

        LanguagePreference.system.apply(defaults)
        XCTAssertNil(defaults.persistentDomain(forName: name)?[LanguagePreference.appleLanguagesKey])
        XCTAssertFalse(LanguagePreference.system.needsRelaunch(defaults))
    }

    /// неизвестное значение означает «как в системе», а не молчаливый русский
    func testUnknownPreferenceFollowsTheSystem() {
        XCTAssertEqual(LanguagePreference.resolve(nil), .system)
        XCTAssertEqual(LanguagePreference.resolve("klingon"), .system)
        XCTAssertEqual(LanguagePreference.resolve("en"), .en)
    }

    /// язык выбирается в программе, а не системой: каждый должен приходить из своего бандла
    func testLanguageSelectsItsOwnBundle() {
        XCTAssertEqual(L.text("start", .ru), "Начать")
        XCTAssertEqual(L.text("start", .en), "Start")
        XCTAssertEqual(L.format("update.available", .en, ["v": "1.7.0"]), "Version 1.7.0 is available.")
    }

    /// подстановка идёт одним проходом: подставленное значение само может содержать {token},
    /// и повторно оно разбираться не должно, а неизвестный токен остаётся в тексте как есть
    func testFormatSubstitutesEachPlaceholderOnce() {
        XCTAssertEqual(
            L.format("update.available", .en, ["v": "{code}", "code": "1.7.0"]),
            "Version {code} is available."
        )
        XCTAssertEqual(L.format("update.available", .en, ["code": "1.7.0"]), "Version {v} is available.")
    }

    func testEveryKeyUsedInCodeExists() throws {
        let known: Set<String> = try Set(table(.ru).keys).union(pluralTable(.ru).keys)
        // граница перед t обязательна, иначе под шаблон попадают Text( и keyboardShortcut(
        let pattern = try NSRegularExpression(pattern: #"(?:L\.text|L\.format|L\.plural|(?<![\w.])t)\(\s*"([\w.]+)""#)
        // обход рекурсивный: файл в новой подпапке иначе молча выпадет из проверки
        let walker: FileManager.DirectoryEnumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: sourcesDirectory, includingPropertiesForKeys: nil))
        let files: [URL] = walker.compactMap { entry in entry as? URL }.filter { url in url.pathExtension == "swift" }
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
