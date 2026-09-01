import AppKit
import SwiftUI

@main
struct AVTHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(LanguagePreference.storageKey) private var appLanguageRaw: String = LanguagePreference.system.rawValue

    private var language: AppLanguage {
        AppLanguage.resolve(appLanguageRaw)
    }

    var body: some Scene {
        // каждое окно единственное по смыслу, поэтому Window, а не WindowGroup: группа на каждый
        // openWindow заводит ещё одну копию, а Window поднимает уже открытую.
        // фильтр внешних событий остаётся на всех сценах: сцена без него забирает открытие файлов
        // из Finder себе и выскакивает вместо главного окна, а десять серий подряд превращались бы
        // в десять окон вместо одной очереди
        Window("AVT_helper", id: MainWindow.identifier) {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .handlesExternalEvents(matching: ["avt.main"])
        .commands {
            AppMenuCommands()
        }

        // заголовки вспомогательных окон видны в меню «Окно», поэтому берутся из тех же
        // ресурсов, что и остальной интерфейс: строковый литерал остался бы английским навсегда
        Window(L.text("about", language), id: "about") {
            AboutWindow()
        }
        .defaultSize(width: 420, height: 320)
        .handlesExternalEvents(matching: ["avt.about"])

        Window(L.text("qa", language), id: "qa") {
            QAWindow()
        }
        .defaultSize(width: 540, height: 380)
        .handlesExternalEvents(matching: ["avt.qa"])

        Settings {
            SettingsWindow()
        }
    }
}

enum MainWindow {
    static let identifier: String = "main"
}

/// идёт ли прямо сейчас запись файлов. флаг общий на программу: выход обязан спросить
/// подтверждение, а знает о работе не он, а тот, кто пишет. ProcessingModel выставляет его
/// на время прогона очереди, лист разролёвки - на время записи DOCX
@MainActor
enum WorkGuard {
    static var isBusy: Bool = false
}

extension Notification.Name {
    /// просит главное окно открыть файлы из object, а без него - показать диалог выбора
    static let openSubtitleFiles = Notification.Name("app.openSubtitleFiles")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// выбранный язык переносится в AppleLanguages ещё до появления окон: у тех, кто выбрал его
    /// в прошлой версии, ключа нет, и меню осталось бы на языке системы навсегда.
    /// этот запуск уже не изменится, а следующий откроется целиком на выбранном языке
    func applicationWillFinishLaunching(_ notification: Notification) {
        let preference: LanguagePreference = LanguagePreference.resolve(
            UserDefaults.standard.string(forKey: LanguagePreference.storageKey)
        )
        if preference.needsRelaunch() {
            preference.apply()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// выход посреди записи обрывает файл на середине, поэтому во время работы он требует
    /// подтверждения. это же спрашивается и при закрытии последнего окна: оно ведёт к выходу
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard WorkGuard.isBusy else {
            return .terminateNow
        }
        let language: AppLanguage = AppLanguage.resolve(UserDefaults.standard.string(forKey: LanguagePreference.storageKey))
        let alert: NSAlert = NSAlert()
        alert.messageText = L.text("quit.busy.title", language)
        // первой кнопкой продолжение работы: она же кнопка по умолчанию, и случайный Enter
        // не обрывает запись
        alert.addButton(withTitle: L.text("quit.busy.keepWorking", language))
        alert.addButton(withTitle: L.text("quit.busy.quit", language))
        return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
    }

    /// файлы, открытые двойным кликом в Finder или перетащенные на иконку
    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }
        NotificationCenter.default.post(name: .openSubtitleFiles, object: urls)
    }
}

// MARK: - действия окна для меню

/// действия главного окна, поднятые в меню. nil означает, что окна нет или действие сейчас
/// невозможно, и пункт меню гаснет сам
struct WindowActions {
    let start: (() -> Void)?
    let assign: (() -> Void)?
}

struct WindowActionsKey: FocusedValueKey {
    typealias Value = WindowActions
}

extension FocusedValues {
    var windowActions: WindowActions? {
        get { self[WindowActionsKey.self] }
        set { self[WindowActionsKey.self] = newValue }
    }
}

// MARK: - меню

struct AppMenuCommands: Commands {
    @AppStorage(LanguagePreference.storageKey) private var appLanguageRaw: String = LanguagePreference.system.rawValue
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.windowActions) private var actions
    @ObservedObject private var recent: RecentFiles = .shared

    private var language: AppLanguage {
        AppLanguage.resolve(appLanguageRaw)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            // у пунктов меню свои ключи: рядом стоят системные пункты в title case,
            // а многоточие обещает диалог, который откроется по нажатию
            Button(L.text("menu.openSubtitles", language)) {
                NotificationCenter.default.post(name: .openSubtitleFiles, object: nil)
            }
            .keyboardShortcut("o")

            Menu(L.text("openRecent", language)) {
                ForEach(recent.urls, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        NotificationCenter.default.post(name: .openSubtitleFiles, object: [url])
                    }
                }
                Divider()
                Button(L.text("openRecent.clear", language)) {
                    recent.clear()
                }
            }
            .disabled(recent.urls.isEmpty)
        }

        // главные действия окна обязаны быть в меню: оттуда их находит поиск по меню,
        // Accessibility и тот, кто не знает про кнопку в углу
        CommandMenu(L.text("menu.process", language)) {
            Button(L.text("start", language)) {
                actions?.start?()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(actions?.start == nil)

            Button(L.text("menu.makeRoleAssignment", language)) {
                actions?.assign?()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(actions?.assign == nil)
        }

        CommandGroup(replacing: .appInfo) {
            Button(L.text("about", language)) {
                openWindow(id: "about")
            }
            UpdateCheckButton(language: language)
        }

        // главное окно закрывается вместе с остальными, и без этого пункта вернуть его нечем
        CommandGroup(after: .windowList) {
            Button(L.text("menu.mainWindow", language)) {
                openWindow(id: MainWindow.identifier)
            }
            .keyboardShortcut("0", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button(L.text("qa", language)) {
                openWindow(id: "qa")
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}
