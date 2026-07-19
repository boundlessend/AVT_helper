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

struct AboutView: View {
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss

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

            Text("@boundlessend")
                .fontWeight(.semibold)

            Spacer()

            HStack {
                Spacer()
                Button(L.text("settings.close", language)) {
                    dismiss()
                }
            }
        }
        .padding(16)
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
            HStack {
                Label(L.text("qa", language), systemImage: "questionmark.circle")
                    .font(.title2.weight(.bold))
                Spacer()
                Button(L.text("settings.close", language)) {
                    dismiss()
                }
            }

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
            HStack {
                Label(L.text("settings", language), systemImage: "gearshape")
                    .font(.title2.weight(.bold))
                Spacer()
                Button(L.text("settings.close", language)) {
                    dismiss()
                }
            }

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
