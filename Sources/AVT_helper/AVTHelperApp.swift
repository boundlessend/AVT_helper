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
                .frame(width: 400, height: 300)
        }
        .defaultSize(width: 400, height: 300)
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

/// держит результат импорта и выполняет тяжёлые импорт/экспорт вне главного потока
@MainActor
final class ProcessingModel: ObservableObject {
    @Published var importedSubtitle: ImportedSubtitle?
    @Published var roles: [String] = []
    @Published var status: String = ""
    @Published var isWorking: Bool = false
    @Published var lastCreatedFiles: [String] = []

    func log(_ message: String) {
        status = message
    }

    func importFile(path: String, language: AppLanguage) async {
        isWorking = true
        do {
            let imported: ImportedSubtitle = try await Task.detached(priority: .userInitiated) {
                try SubtitleImporter.importFile(path: path, language: language)
            }.value
            importedSubtitle = imported
            roles = imported.allRoles(language)
            status = "\(L.text("imported", language)) \(imported.lines.count) \(L.text("lines", language)) \(imported.sourceType.rawValue)."
        } catch {
            importedSubtitle = nil
            roles = []
            status = L.describe(error, language)
        }
        isWorking = false
    }

    func export(outputFolder: String, settings: ExportSettings, language: AppLanguage) async -> Bool {
        guard let subtitle: ImportedSubtitle = importedSubtitle else {
            status = SubtitleError.exportFailed(L.text("error.noInputSelected", language)).message(language)
            return false
        }
        isWorking = true
        var succeeded: Bool = false
        do {
            let created: [String] = try await Task.detached(priority: .userInitiated) {
                try SubtitleExporter.export(subtitle: subtitle, outputFolder: outputFolder, settings: settings, language: language)
            }.value
            lastCreatedFiles = created
            status = "\(L.text("ready", language)). \(L.text("createdFiles", language)): \(created.count)"
            succeeded = true
        } catch {
            status = L.describe(error, language)
        }
        isWorking = false
        return succeeded
    }
}

struct ContentView: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw: String = AppLanguage.ru.rawValue
    @StateObject private var model: ProcessingModel = ProcessingModel()
    @State private var inputPath: String = ""
    @State private var outputFolder: String = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory()
    @State private var selectedRoles: Set<String> = []
    @AppStorage("exportAss") private var exportAss: Bool = false
    @AppStorage("exportSrt") private var exportSrt: Bool = false
    @AppStorage("exportVtt") private var exportVtt: Bool = false
    @AppStorage("exportDocx") private var exportDocx: Bool = false
    @AppStorage("srtFullWithRoles") private var srtFullWithRoles: Bool = false
    @AppStorage("srtSeparateFiles") private var srtSeparateFiles: Bool = false
    @AppStorage("srtSeparateWithRoles") private var srtSeparateWithRoles: Bool = false
    @AppStorage("openFolderAfterProcessing") private var openFolderAfterProcessing: Bool = false
    @AppStorage("closeProgramAfterProcessing") private var closeProgramAfterProcessing: Bool = false
    @State private var showDoneAlert: Bool = false
    @State private var showRoleAssignment: Bool = false
    @State private var isDropTargeted: Bool = false

    private var language: AppLanguage {
        AppLanguage.resolve(appLanguageRaw)
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
                if model.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(model.status.isEmpty ? t("ready") : model.status)
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
        } message: {
            Text(
                model.lastCreatedFiles
                    .map { path in URL(fileURLWithPath: path).lastPathComponent }
                    .joined(separator: "\n")
            )
        }
        .sheet(isPresented: $showRoleAssignment) {
            if let subtitle: ImportedSubtitle = model.importedSubtitle {
                RoleAssignmentView(
                    subtitle: subtitle,
                    outputFolder: outputFolder,
                    language: language,
                    onComplete: { path in
                        model.lastCreatedFiles = [path]
                        model.log("\(t("createdAssignment")): \(path)")
                        showDoneAlert = true
                    },
                    onError: { message in
                        model.log(message)
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
                    .disabled(model.importedSubtitle == nil || model.roles.isEmpty)
                }
                .disabled(model.isWorking)
            }
        }
    }

    private var rolesPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("assignedRoles"))
                    .font(.headline)
                List(model.roles, id: \.self) { role in
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
                TextField("", text: $outputFolder)
                    .textFieldStyle(.roundedBorder)
                Text("\(t("source")): \(model.importedSubtitle?.sourceType.rawValue ?? t("notSelected"))")
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
        .background(isDropTargeted ? Color.accentColor.opacity(0.15) : Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6, 4]))
                .foregroundStyle(isDropTargeted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
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
                List(model.roles, id: \.self, selection: $selectedRoles) { role in
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
            model.log("\(t("outputFolderLog")): \(url.path)")
        }
    }

    private func reloadInput(path: String) {
        selectedRoles = []
        Task {
            await model.importFile(path: path, language: language)
        }
    }

    private func runExport() {
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
        Task {
            if await model.export(outputFolder: outputFolder, settings: settings, language: language) {
                showDoneAlert = true
            }
        }
    }

    private func handleInputDrop(providers: [NSItemProvider]) -> Bool {
        guard
            let provider: NSItemProvider = providers.first(where: { item in
                item.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            })
        else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            if let error {
                DispatchQueue.main.async {
                    model.log(error.localizedDescription)
                }
                return
            }

            let url: URL?
            if let data: Data = item as? Data,
                let text: String = String(data: data, encoding: .utf8)
            {
                url = URL(string: text)
            } else {
                url = item as? URL
            }

            guard let path: String = url?.path else {
                DispatchQueue.main.async {
                    model.log(t("dropReadError"))
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

}

struct AppMenuCommands: Commands {
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw: String = AppLanguage.ru.rawValue
    @Environment(\.openWindow) private var openWindow

    private var language: AppLanguage {
        AppLanguage.resolve(appLanguageRaw)
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
