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
        WindowGroup(id: MainWindow.identifier) {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        // без этого macOS открывает по окну на каждый файл, выбранный в Finder,
        // и десять серий превращаются в десять окон вместо одной очереди
        .handlesExternalEvents(matching: ["avt.main"])
        .commands {
            AppMenuCommands()
        }

        // заголовки вспомогательных окон видны в меню «Окно», поэтому берутся из тех же
        // ресурсов, что и остальной интерфейс: строковый литерал остался бы английским навсегда
        // вспомогательные окна объявлены группами, а не Window: сцена Window перехватывает
        // открытие файлов из Finder, которое главное окно у себя отключило, и выскакивает
        // вместо него. группа честно смотрит на условие и файлы не забирает
        WindowGroup(L.text("about", language), id: "about") {
            AboutWindow()
        }
        .defaultSize(width: 420, height: 320)
        .handlesExternalEvents(matching: ["avt.about"])

        WindowGroup(L.text("qa", language), id: "qa") {
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
    let open: () -> Void
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
    @ObservedObject private var updates: UpdateController = .shared
    @ObservedObject private var recent: RecentFiles = .shared

    private var language: AppLanguage {
        AppLanguage.resolve(appLanguageRaw)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L.text("openSubtitles", language)) {
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

            Button(L.text("makeRoleAssignment", language)) {
                actions?.assign?()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(actions?.assign == nil)
        }

        CommandGroup(replacing: .appInfo) {
            Button(L.text("about", language)) {
                openWindow(id: "about")
            }
            Button(L.text("update.check", language)) {
                Task { await updates.checkNow(language: language) }
            }
            .disabled(updates.isChecking)
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
