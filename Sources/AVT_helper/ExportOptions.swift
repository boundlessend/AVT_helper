import Foundation

/// настройки выгрузки, живущие в UserDefaults между запусками:
/// класс, потому что это доступ к внешнему хранилищу, а не логика приложения
@MainActor
final class ExportOptions: ObservableObject {
    private enum Key {
        static let ass: String = "exportAss"
        static let srt: String = "exportSrt"
        static let vtt: String = "exportVtt"
        static let docx: String = "exportDocx"
        static let srtFullWithRoles: String = "srtFullWithRoles"
        static let srtSeparateFiles: String = "srtSeparateFiles"
        static let srtSeparateWithRoles: String = "srtSeparateWithRoles"
        static let openFolderAfter: String = "openFolderAfterProcessing"
        static let closeAppAfter: String = "closeProgramAfterProcessing"
        static let outputFolder: String = "outputFolder"
    }

    /// путь папки выгрузки хранится как обычная строка, потому что программа не в песочнице.
    /// если она когда-нибудь туда переедет, одного пути станет мало: понадобится
    /// security-scoped bookmark, иначе после перезапуска доступа к папке не будет
    private let defaults: UserDefaults

    @Published var ass: Bool { didSet { defaults.set(ass, forKey: Key.ass) } }
    @Published var srt: Bool { didSet { defaults.set(srt, forKey: Key.srt) } }
    @Published var vtt: Bool { didSet { defaults.set(vtt, forKey: Key.vtt) } }
    @Published var docx: Bool { didSet { defaults.set(docx, forKey: Key.docx) } }
    @Published var srtFullWithRoles: Bool { didSet { defaults.set(srtFullWithRoles, forKey: Key.srtFullWithRoles) } }
    @Published var srtSeparateFiles: Bool { didSet { defaults.set(srtSeparateFiles, forKey: Key.srtSeparateFiles) } }
    @Published var srtSeparateWithRoles: Bool { didSet { defaults.set(srtSeparateWithRoles, forKey: Key.srtSeparateWithRoles) } }
    @Published var openFolderAfter: Bool { didSet { defaults.set(openFolderAfter, forKey: Key.openFolderAfter) } }
    @Published var closeAppAfter: Bool { didSet { defaults.set(closeAppAfter, forKey: Key.closeAppAfter) } }
    @Published var outputFolder: String { didSet { defaults.set(outputFolder, forKey: Key.outputFolder) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ass = defaults.bool(forKey: Key.ass)
        srt = defaults.object(forKey: Key.srt) as? Bool ?? true
        vtt = defaults.bool(forKey: Key.vtt)
        docx = defaults.bool(forKey: Key.docx)
        srtFullWithRoles = defaults.bool(forKey: Key.srtFullWithRoles)
        srtSeparateFiles = defaults.bool(forKey: Key.srtSeparateFiles)
        srtSeparateWithRoles = defaults.bool(forKey: Key.srtSeparateWithRoles)
        openFolderAfter = defaults.bool(forKey: Key.openFolderAfter)
        closeAppAfter = defaults.bool(forKey: Key.closeAppAfter)
        outputFolder =
            defaults.string(forKey: Key.outputFolder)
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory()

        // до вложенности префикс роли включался сам по себе: сохраняем прежний результат такой настройки
        if srtSeparateWithRoles && !srtSeparateFiles {
            srtSeparateFiles = true
        }
    }

    var hasFormat: Bool {
        ass || srt || vtt || docx
    }

    func settings(selectedRoles: Set<String>, roleHighlights: [String: WordHighlightColor]) -> ExportSettings {
        ExportSettings(
            exportAss: ass,
            exportSrt: srt,
            exportVtt: vtt,
            exportDocx: docx,
            srtFullWithRoles: srtFullWithRoles,
            srtSeparateFiles: srtSeparateFiles,
            srtSeparateWithRoles: srtSeparateWithRoles,
            selectedRoles: selectedRoles,
            roleHighlights: roleHighlights
        )
    }
}
