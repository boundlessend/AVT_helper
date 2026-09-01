import AppKit
import Foundation
import UniformTypeIdentifiers

/// «Открыть недавние» ведёт NSDocumentController: он следит за переименованиями файлов,
/// рисует значки и переживает переустановку, чего свой список в UserDefaults не умеет
@MainActor
final class RecentFiles: ObservableObject {
    static let shared: RecentFiles = RecentFiles()

    @Published private(set) var urls: [URL] = NSDocumentController.shared.recentDocumentURLs

    private init() {}

    func remember(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        urls = NSDocumentController.shared.recentDocumentURLs
    }

    func clear() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        urls = NSDocumentController.shared.recentDocumentURLs
    }
}

enum AppLimits {
    /// максимальный размер импортируемого файла субтитров
    static let maxSubtitleFileBytes: UInt64 = 50 * 1024 * 1024
    /// запас имени файла в байтах: 255 это предел файловой системы, остальное уходит
    /// на суффикс различения и расширение
    static let maxFileNameBytes: Int = 200
}

enum OutputFolder {
    /// папка выгрузки годится, только если путь абсолютный, ведёт в существующий каталог и в него можно писать:
    /// относительный путь создал бы файлы неизвестно где, а каталог без права записи ронял бы прогон посередине
    static func isUsable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists: Bool = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return path.hasPrefix("/") && exists && isDirectory.boolValue && FileManager.default.isWritableFile(atPath: path)
    }
}

enum Roles {
    /// метка нераспознанной роли на выбранном языке
    static func unassigned(_ language: AppLanguage) -> String {
        L.text("role.unassigned", language)
    }

    /// правда ли, что поле Name пришло из нашего же экспорта, где нераспознанная роль
    /// записана меткой. проверка нужна только импорту ASS: без неё круг через программу
    /// превращает отсутствие роли в роль с именем «Не назначено»
    static func isOwnPlaceholder(_ name: String) -> Bool {
        AppLanguage.allCases.contains { language in
            name.caseInsensitiveCompare(L.text("role.unassigned", language)) == .orderedSame
        }
    }
}

enum AppInfo {
    /// строка копирайта из Info.plist: в окне «О программе» она обязана совпадать с бандлом
    static var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
    }

    /// версия релиза: она же сравнивается с версией последнего релиза на GitHub
    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// номер сборки и её происхождение: «релиз» или коммит, из которого собрана эта копия
    static var buildLabel: String {
        let build: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let stage: String = Bundle.main.infoDictionary?["AVTBuildStage"] as? String ?? "dev"
        return stage == "release" ? build : "\(build), \(stage)"
    }
}

/// что программа берётся читать. один список на панель открытия, на перетаскивание
/// и на объявление типов документов в Info.plist
enum SubtitleFormats {
    static let extensions: [String] = ["ass", "ssa", "srt", "vtt", "srp"]

    static let contentTypes: [UTType] = extensions.compactMap { ext in UTType(filenameExtension: ext) }

    static func accepts(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    /// имя без разбора URL: перетаскивание сообщает его до того, как выдаст сам файл
    static func accepts(name: String) -> Bool {
        extensions.contains((name as NSString).pathExtension.lowercased())
    }
}
