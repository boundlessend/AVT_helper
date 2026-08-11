import SwiftUI

struct AboutWindow: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw: String = AppLanguage.ru.rawValue

    private var language: AppLanguage {
        AppLanguage.resolve(appLanguageRaw)
    }

    var body: some View {
        AboutView(language: language)
    }
}

struct QAWindow: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw: String = AppLanguage.ru.rawValue

    private var language: AppLanguage {
        AppLanguage.resolve(appLanguageRaw)
    }

    var body: some View {
        QAView(language: language)
    }
}

struct SettingsWindow: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw: String = AppLanguage.ru.rawValue

    var body: some View {
        SettingsView(languageRaw: $appLanguageRaw)
    }
}

/// общий заголовок вспомогательных окон с кнопкой закрытия
struct WindowHeader: View {
    let title: String
    let systemImage: String?
    let closeTitle: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            if let systemImage: String = systemImage {
                Label(title, systemImage: systemImage)
                    .font(.title2.weight(.bold))
            } else {
                Text(title)
                    .font(.title2.weight(.bold))
            }
            Spacer()
            Button(closeTitle, action: onClose)
        }
    }
}

struct AboutView: View {
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var updateStatus: String = ""
    @State private var updatePageUrl: URL?
    @State private var isCheckingUpdates: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AVT_helper")
                        .font(.title2.weight(.bold))
                    Text("\(L.text("version", language)) \(AppInfo.shortVersion)")
                        .foregroundStyle(.secondary)
                }
            }

            Text(L.text("about.description", language))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(L.text("update.check", language)) {
                    checkForUpdates()
                }
                .disabled(isCheckingUpdates)
                if isCheckingUpdates {
                    ProgressView()
                        .controlSize(.small)
                }
                if let updatePageUrl: URL = updatePageUrl {
                    Button(L.text("update.download", language)) {
                        NSWorkspace.shared.open(updatePageUrl)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if !updateStatus.isEmpty {
                Text(updateStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("@boundlessend")
                .fontWeight(.semibold)

            Spacer()

            HStack {
                Spacer()
                Button(L.text("close", language)) {
                    dismiss()
                }
            }
        }
        .padding(16)
    }

    private func checkForUpdates() {
        isCheckingUpdates = true
        updateStatus = ""
        updatePageUrl = nil
        Task {
            do {
                let release: UpdateChecker.ReleaseInfo = try await UpdateChecker.fetchLatest()
                if release.version == AppInfo.shortVersion {
                    updateStatus = L.text("update.latest", language)
                } else {
                    updateStatus = L.format("update.available", language, ["v": release.version])
                    updatePageUrl = release.pageUrl
                }
            } catch {
                updateStatus = L.describe(error, language)
            }
            isCheckingUpdates = false
        }
    }
}

struct QAView: View {
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss

    private var items: [(String, String)] {
        [
            ("qa.q1", "qa.a1"),
            ("qa.q2", "qa.a2"),
            ("qa.q3", "qa.a3"),
            ("qa.q4", "qa.a4"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WindowHeader(
                title: L.text("qa", language),
                systemImage: "questionmark.circle",
                closeTitle: L.text("close", language),
                onClose: { dismiss() }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items, id: \.0) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.text(item.0, language))
                                .fontWeight(.semibold)
                            Text(L.text(item.1, language))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(16)
    }
}

struct SettingsView: View {
    @Binding var languageRaw: String
    @Environment(\.dismiss) private var dismiss

    private var language: AppLanguage {
        AppLanguage.resolve(languageRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WindowHeader(
                title: L.text("settings", language),
                systemImage: "gearshape",
                closeTitle: L.text("close", language),
                onClose: { dismiss() }
            )

            Picker(L.text("settings.language", language), selection: $languageRaw) {
                ForEach(AppLanguage.allCases) { item in
                    Text(item.title).tag(item.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Spacer()
        }
        .padding(16)
    }
}
