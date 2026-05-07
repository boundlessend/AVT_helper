import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct AVTHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1040, minHeight: 720)
        }
        .windowStyle(.titleBar)
        .commands {
            AppMenuCommands()
        }

        Window("About", id: "about") {
            AboutWindow()
                .frame(width: 380, height: 220)
        }
        .defaultSize(width: 380, height: 220)
        .windowResizability(.contentSize)

        Window("Q&A", id: "qa") {
            QAWindow()
                .frame(width: 520, height: 340)
        }
        .defaultSize(width: 520, height: 340)
        .windowResizability(.contentSize)

        Window("Settings", id: "settings") {
            SettingsWindow()
                .frame(width: 380, height: 190)
        }
        .defaultSize(width: 380, height: 190)
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct ContentView: View {
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.ru.rawValue
    @State private var inputPath: String = ""
    @State private var outputFolder: String = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory()
    @State private var importedSubtitle: ImportedSubtitle?
    @State private var roles: [String] = []
    @State private var selectedRoles: Set<String> = []
    @State private var exportAss: Bool = false
    @State private var exportSrt: Bool = false
    @State private var exportVtt: Bool = false
    @State private var exportDocx: Bool = false
    @State private var srtFullWithRoles: Bool = false
    @State private var srtSeparateFiles: Bool = false
    @State private var srtSeparateWithRoles: Bool = false
    @State private var openFolderAfterProcessing: Bool = false
    @State private var closeProgramAfterProcessing: Bool = false
    @State private var showDoneAlert: Bool = false
    @State private var showRoleAssignment: Bool = false
    @State private var status: String = L.text("ready", .ru)

    private var language: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .ru
    }

    private func t(_ key: String) -> String {
        L.text(key, language)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Grid(alignment: .top, horizontalSpacing: 14, verticalSpacing: 14) {
                    GridRow {
                        headerPanel
                            .gridCellColumns(2)
                        roleSelectionPanel
                    }

                    GridRow {
                        pathsPanel
                        exportPanel
                        docxPanel
                    }

                    GridRow {
                        rolesPanel
                            .gridCellColumns(3)
                    }
                }
                .padding(18)
            }

            HStack {
                Text(status)
                    .lineLimit(2)
                Spacer()
                Text("@boundlessend")
                    .fontWeight(.semibold)
            }
            .font(.footnote)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .alert(t("done"), isPresented: $showDoneAlert) {
            Button(t("ok")) {
                completeProcessing()
            }
        }
        .sheet(isPresented: $showRoleAssignment) {
            if let subtitle: ImportedSubtitle = importedSubtitle {
                RoleAssignmentView(
                    subtitle: subtitle,
                    outputFolder: outputFolder,
                    language: language,
                    onComplete: { path in
                        appendLog("\(t("createdAssignment")): \(path)")
                        showDoneAlert = true
                    },
                    onError: { message in
                        appendLog(message)
                    }
                )
                .frame(minWidth: 860, minHeight: 620)
            }
        }
    }

    private var headerPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("AVT_helper")
                    .font(.largeTitle.weight(.bold))
                Text("ASS / SSA / SRT / VTT / SRP → ASS / SRT / VTT / DOCX")
                    .foregroundStyle(.secondary)
                HStack {
                    Button(t("openSubtitles")) {
                        chooseInputFile()
                    }
                    Button(t("chooseOutputFolder")) {
                        chooseOutputFolder()
                    }
                    Button(t("start")) {
                        runExport()
                    }
                    .keyboardShortcut(.return)
                    Button(t("makeRoleAssignment")) {
                        showRoleAssignment = true
                    }
                    .disabled(importedSubtitle == nil || roles.isEmpty)
                }
            }
        }
    }

    private var rolesPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("assignedRoles"))
                    .font(.headline)
                List(roles, id: \.self) { role in
                    Text(role)
                }
                .frame(height: 220)
            }
        }
    }

    private var pathsPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("paths"))
                    .font(.headline)
                Text(t("inputFile"))
                    .foregroundStyle(.secondary)
                inputDropZone
                Text(t("outputFolder"))
                    .foregroundStyle(.secondary)
                TextField("", text: .constant(outputFolder))
                    .textFieldStyle(.roundedBorder)
                Text("\(t("source")): \(importedSubtitle?.sourceType.rawValue ?? t("notSelected"))")
                    .fontWeight(.semibold)
            }
        }
    }

    private var inputDropZone: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(inputPath.isEmpty ? t("dropHint") : inputPath)
                .lineLimit(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("ASS, SSA, SRT, VTT, SRP")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .foregroundStyle(.secondary)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            handleInputDrop(providers: providers)
        }
    }

    private var exportPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("export"))
                    .font(.headline)
                Toggle(t("toAss"), isOn: $exportAss)
                Toggle(t("toSrt"), isOn: $exportSrt)
                Toggle(t("toVtt"), isOn: $exportVtt)
                Toggle(t("toDocx"), isOn: $exportDocx)
                Divider()
                Toggle(t("openFolderAfter"), isOn: $openFolderAfterProcessing)
                Toggle(t("closeAppAfter"), isOn: $closeProgramAfterProcessing)
            }
        }
    }

    private var docxPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("settings"))
                    .font(.headline)
                Text(t("srtSettings"))
                    .font(.headline)
                Toggle(t("fullWithRoles"), isOn: $srtFullWithRoles)
                Toggle(t("separateByRole"), isOn: $srtSeparateFiles)
                Toggle(t("separateWithPrefix"), isOn: $srtSeparateWithRoles)
            }
        }
    }

    private var roleSelectionPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("rolesForSeparateExport"))
                    .font(.headline)
                List(roles, id: \.self, selection: $selectedRoles) { role in
                    Text(role)
                }
                .frame(height: 132)
            }
        }
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func chooseInputFile() {
        let panel: NSOpenPanel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["ass", "ssa", "srt", "vtt", "srp"].compactMap { ext in
            UTType(filenameExtension: ext)
        }
        if panel.runModal() == .OK, let url: URL = panel.url {
            inputPath = url.path
            reloadInput(path: url.path)
        }
    }

    private func chooseOutputFolder() {
        let panel: NSOpenPanel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url: URL = panel.url {
            outputFolder = url.path
            appendLog("\(t("outputFolderLog")): \(url.path)")
        }
    }

    private func reloadInput(path: String) {
        do {
            let imported: ImportedSubtitle = try SubtitleImporter.importFile(path: path)
            importedSubtitle = imported
            roles = imported.allRoles
            selectedRoles = []
            appendLog("\(t("imported")) \(imported.lines.count) \(t("lines")) \(imported.sourceType.rawValue).")
        } catch {
            appendLog(error.localizedDescription)
        }
    }

    private func runExport() {
        do {
            guard let subtitle: ImportedSubtitle = importedSubtitle else {
                throw SubtitleError.exportFailed("Сначала выберите исходный файл.")
            }
            let settings: ExportSettings = ExportSettings(
                exportAss: exportAss,
                exportSrt: exportSrt,
                exportVtt: exportVtt,
                exportDocx: exportDocx,
                srtFullWithRoles: srtFullWithRoles,
                srtSeparateFiles: srtSeparateFiles,
                srtSeparateWithRoles: srtSeparateWithRoles,
                selectedRoles: selectedRoles
            )
            let created: [String] = try SubtitleExporter.export(subtitle: subtitle, outputFolder: outputFolder, settings: settings)
            for path in created {
                appendLog("\(t("created")): \(path)")
            }
            appendLog("\(t("ready")). \(t("createdFiles")): \(created.count)")
            showDoneAlert = true
        } catch {
            appendLog(error.localizedDescription)
        }
    }

    private func handleInputDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider: NSItemProvider = providers.first(where: { item in
            item.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            if let error {
                DispatchQueue.main.async {
                    appendLog(error.localizedDescription)
                }
                return
            }

            let url: URL?
            if let data: Data = item as? Data,
               let text: String = String(data: data, encoding: .utf8) {
                url = URL(string: text)
            } else {
                url = item as? URL
            }

            guard let path: String = url?.path else {
                DispatchQueue.main.async {
                    appendLog(t("dropReadError"))
                }
                return
            }

            DispatchQueue.main.async {
                inputPath = path
                reloadInput(path: path)
            }
        }

        return true
    }

    private func completeProcessing() {
        if openFolderAfterProcessing {
            NSWorkspace.shared.open(URL(fileURLWithPath: outputFolder))
        }
        if closeProgramAfterProcessing {
            NSApp.terminate(nil)
        }
    }

    private func appendLog(_ message: String) {
        status = message
    }

}

struct AppMenuCommands: Commands {
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.ru.rawValue
    @Environment(\.openWindow) private var openWindow

    private var language: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .ru
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button {
                openWindow(id: "about")
            } label: {
                Label(L.text("about", language), systemImage: "info.circle")
            }
            Button {
                openWindow(id: "qa")
            } label: {
                Label(L.text("qa", language), systemImage: "questionmark.circle")
            }
            Button {
                openWindow(id: "settings")
            } label: {
                Label(L.text("settings", language), systemImage: "gearshape")
            }
        }
    }
}

enum AppCache {
    static func resetTemporaryFiles() {
        let tempUrl: URL = FileManager.default.temporaryDirectory
        let items: [URL] = (try? FileManager.default.contentsOfDirectory(at: tempUrl, includingPropertiesForKeys: nil)) ?? []
        for item in items where item.lastPathComponent.hasPrefix("AVT_helper_docx_") {
            try? FileManager.default.removeItem(at: item)
        }
    }
}
