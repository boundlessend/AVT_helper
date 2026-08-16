import AppKit
import SwiftUI

struct AboutWindow: View {
    @AppStorage(LanguagePreference.storageKey) private var appLanguageRaw: String = LanguagePreference.system.rawValue

    var body: some View {
        AboutView(language: AppLanguage.resolve(appLanguageRaw))
    }
}

struct QAWindow: View {
    @AppStorage(LanguagePreference.storageKey) private var appLanguageRaw: String = LanguagePreference.system.rawValue

    var body: some View {
        QAView(language: AppLanguage.resolve(appLanguageRaw))
    }
}

struct SettingsWindow: View {
    @AppStorage(LanguagePreference.storageKey) private var appLanguageRaw: String = LanguagePreference.system.rawValue

    var body: some View {
        SettingsView(preferenceRaw: $appLanguageRaw)
    }
}

/// проверка обновлений: одна кнопка на меню программы и окно «О программе»,
/// чтобы условие занятости не разъехалось между ними
struct UpdateCheckButton: View {
    let language: AppLanguage
    @ObservedObject private var updates: UpdateController = .shared

    var body: some View {
        Button(L.text("update.check", language)) {
            Task { await updates.checkNow(language: language) }
        }
        .disabled(updates.isChecking)
    }
}

struct AboutView: View {
    let language: AppLanguage
    @ObservedObject private var updates: UpdateController = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AVT_helper")
                        .font(.title2.weight(.bold))
                    Text("\(L.text("version", language)) \(AppInfo.shortVersion) (\(AppInfo.buildLabel))")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Text(L.text("about.description", language))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                UpdateCheckButton(language: language)
                if updates.isChecking {
                    ProgressView()
                        .controlSize(.small)
                }
                if let release: UpdateChecker.ReleaseInfo = updates.available {
                    Button(L.text("update.download", language)) {
                        NSWorkspace.shared.open(release.pageUrl)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if !updates.message.isEmpty {
                Text(updates.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(AppInfo.copyright)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            DismissFooter(language: language)
        }
        .padding(18)
        .frame(minWidth: 400, minHeight: 300)
    }
}

struct QAView: View {
    let language: AppLanguage

    private var items: [(String, String)] {
        [
            ("qa.q1", "qa.a1"),
            ("qa.q2", "qa.a2"),
            ("qa.q3", "qa.a3"),
            ("qa.q4", "qa.a4"),
            ("qa.q5", "qa.a5"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items, id: \.0) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.text(item.0, language))
                                .fontWeight(.semibold)
                            Text(L.text(item.1, language))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            DismissFooter(language: language)
        }
        .padding(18)
        .frame(minWidth: 480, minHeight: 340)
    }
}

/// окно настроек рисует система: заголовок принадлежит окну, а содержимое - сгруппированной форме,
/// как во всех настройках macOS
struct SettingsView: View {
    @Binding var preferenceRaw: String
    @ObservedObject private var updates: UpdateController = .shared
    @State private var showsRelaunch: Bool = false

    private var preference: LanguagePreference {
        LanguagePreference.resolve(preferenceRaw)
    }

    private var language: AppLanguage {
        preference.language
    }

    var body: some View {
        Form {
            Section {
                Picker(L.text("settings.language", language), selection: $preferenceRaw) {
                    ForEach(LanguagePreference.allCases) { item in
                        Text(item.title(language)).tag(item.rawValue)
                    }
                }
            } footer: {
                Text(L.text("settings.language.hint", language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(L.text("settings.autoUpdate", language), isOn: $updates.automatic)
            } footer: {
                Text(L.text("settings.autoUpdate.hint", language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 300)
        .onChange(of: preferenceRaw) { _, _ in
            // меню, панель открытия файла и кнопки алертов рисует AppKit по AppleLanguages,
            // и он читает их один раз при запуске
            showsRelaunch = preference.needsRelaunch()
            preference.apply()
        }
        .alert(L.text("settings.relaunch.title", language), isPresented: $showsRelaunch) {
            Button(L.text("settings.relaunch.now", language)) {
                relaunch()
            }
            Button(L.text("settings.relaunch.later", language), role: .cancel) {}
        } message: {
            Text(L.text("settings.relaunch.message", language))
        }
    }

    private func relaunch() {
        let configuration: NSWorkspace.OpenConfiguration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }
}
