import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct AVTHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 640)
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

        Settings {
            SettingsWindow()
                .frame(width: 380, height: 160)
        }
    }
}

extension Notification.Name {
    /// пункт меню «Открыть субтитры» просит главное окно показать диалог выбора файла
    static let openSubtitleFile = Notification.Name("app.openSubtitleFile")
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
    @Published var roleCounts: [String: Int] = [:]
    @Published var status: String = ""
    @Published var isWorking: Bool = false
    @Published var progress: Double = 0
    @Published var lastCreatedFiles: [String] = []
    /// последние сообщения статуса: без журнала ошибка исчезает под следующим же событием
    @Published private(set) var history: [String] = []

    private var cancelCurrentWork: (() -> Void)?

    func log(_ message: String) {
        status = message
        history.append(message)
        if history.count > 50 {
            history.removeFirst(history.count - 50)
        }
    }

    /// прерывает текущий импорт или экспорт
    func cancel() {
        cancelCurrentWork?()
    }

    func importFile(path: String, language: AppLanguage) async {
        isWorking = true
        progress = 0
        let work: Task<ImportedSubtitle, Error> = Task.detached(priority: .userInitiated) { [self] in
            try SubtitleImporter.importFile(path: path, language: language) { fraction in
                Task { @MainActor in
                    self.progress = fraction
                }
            }
        }
        cancelCurrentWork = { work.cancel() }
        do {
            let imported: ImportedSubtitle = try await work.value
            importedSubtitle = imported
            roles = imported.allRoles(language)
            roleCounts = RoleAssignmentService.roleReplicaCounts(subtitle: imported, language: language)
            log("\(L.text("imported", language)) \(imported.lines.count) \(L.text("lines", language)) \(imported.sourceType.rawValue).")
        } catch is CancellationError {
            forgetInput()
            log(L.text("cancelled", language))
        } catch {
            forgetInput()
            log(L.describe(error, language))
        }
        finishWork()
    }

    func export(outputFolder: String, settings: ExportSettings, language: AppLanguage) async -> Bool {
        guard let subtitle: ImportedSubtitle = importedSubtitle else {
            log(SubtitleError.exportFailed(L.text("error.noInputSelected", language)).message(language))
            return false
        }
        isWorking = true
        progress = 0
        let work: Task<[String], Error> = Task.detached(priority: .userInitiated) { [self] in
            try SubtitleExporter.export(subtitle: subtitle, outputFolder: outputFolder, settings: settings, language: language) { fraction in
                Task { @MainActor in
                    self.progress = fraction
                }
            }
        }
        cancelCurrentWork = { work.cancel() }
        var succeeded: Bool = false
        do {
            let created: [String] = try await work.value
            lastCreatedFiles = created
            log("\(L.text("ready", language)). \(L.text("createdFiles", language)): \(created.count)")
            succeeded = true
        } catch is CancellationError {
            log(L.text("cancelled", language))
        } catch {
            log(L.describe(error, language))
        }
        finishWork()
        return succeeded
    }

    private func forgetInput() {
        importedSubtitle = nil
        roles = []
        roleCounts = [:]
    }

    private func finishWork() {
        cancelCurrentWork = nil
        isWorking = false
        progress = 0
    }
}

struct ContentView: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw: String = AppLanguage.systemDefault.rawValue
    @StateObject private var model: ProcessingModel = ProcessingModel()
    @State private var inputPath: String = ""
    @AppStorage("outputFolder") private var outputFolder: String =
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path
        ?? NSHomeDirectory()
    @State private var selectedRoles: Set<String> = []
    @AppStorage("exportAss") private var exportAss: Bool = false
    @AppStorage("exportSrt") private var exportSrt: Bool = true
    @AppStorage("exportVtt") private var exportVtt: Bool = false
    @AppStorage("exportDocx") private var exportDocx: Bool = false
    @AppStorage("srtFullWithRoles") private var srtFullWithRoles: Bool = false
    @AppStorage("srtSeparateFiles") private var srtSeparateFiles: Bool = false
    @AppStorage("srtSeparateWithRoles") private var srtSeparateWithRoles: Bool = false
    @AppStorage("openFolderAfterProcessing") private var openFolderAfterProcessing: Bool = false
    @AppStorage("closeProgramAfterProcessing") private var closeProgramAfterProcessing: Bool = false
    @State private var showDoneAlert: Bool = false
    @State private var showRoleAssignment: Bool = false
    @State private var showHistory: Bool = false
    @State private var isDropTargeted: Bool = false

    private var language: AppLanguage {
        AppLanguage.resolve(appLanguageRaw)
    }

    private func t(_ key: String) -> String {
        L.text(key, language)
    }

    /// папка выгрузки существует и задана абсолютным путём: относительный путь создал бы папку неизвестно где
    private var outputFolderExists: Bool {
        var isDirectory: ObjCBool = false
        let exists: Bool = FileManager.default.fileExists(atPath: outputFolder, isDirectory: &isDirectory)
        return outputFolder.hasPrefix("/") && exists && isDirectory.boolValue
    }

    /// причина, по которой запуск невозможен; nil означает, что всё готово
    private var startBlockReason: String? {
        if model.importedSubtitle == nil {
            return t("hint.selectInput")
        }
        if !exportAss && !exportSrt && !exportVtt && !exportDocx {
            return t("hint.selectFormat")
        }
        if !outputFolderExists {
            return t("hint.badOutputFolder")
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(spacing: 14) {
                    headerPanel

                    HStack(alignment: .top, spacing: 14) {
                        pathsPanel
                        exportPanel
                        srtPanel
                    }

                    rolesPanel
                }
                .padding(18)
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 10) {
                if model.isWorking {
                    ProgressView(value: model.progress)
                        .frame(width: 130)
                    Text("\(Int(model.progress * 100))%")
                        .monospacedDigit()
                    Button(t("cancel")) {
                        model.cancel()
                    }
                }
                Button {
                    showHistory = true
                } label: {
                    Text(model.status.isEmpty ? t("ready") : model.status)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .help(t("history.hint"))
                .popover(isPresented: $showHistory, arrowEdge: .top) {
                    historyPopover
                }
                Spacer()
                Text("@boundlessend")
                    .fontWeight(.semibold)
            }
            .font(.footnote)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSubtitleFile)) { _ in
            if !model.isWorking {
                chooseInputFile()
            }
        }
        .alert(t("done"), isPresented: $showDoneAlert) {
            Button(t("showInFinder")) {
                revealCreatedFiles()
                completeProcessing()
            }
            Button(t("ok")) {
                completeProcessing()
            }
        } message: {
            Text(createdFilesSummary)
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
                    .fixedSize(horizontal: false, vertical: true)
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
                    .disabled(startBlockReason != nil)
                    .help(startBlockReason ?? t("start"))
                    Button(t("makeRoleAssignment")) {
                        showRoleAssignment = true
                    }
                    .disabled(model.importedSubtitle == nil || model.roles.isEmpty)
                    Spacer(minLength: 0)
                }
                .disabled(model.isWorking)
            }
        }
    }

    /// журнал сообщений: в статус-баре видно только последнее, а ошибка нужна и после следующего события
    private var historyPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t("history"))
                .font(.headline)
            if model.history.isEmpty {
                Text(t("history.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(model.history.enumerated().reversed()), id: \.offset) { item in
                            Text(item.element)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 180)
            }
        }
        .font(.footnote)
        .padding(12)
        .frame(width: 420)
    }

    private var rolesPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(t("roles")) (\(model.roles.count))")
                        .font(.headline)
                    Spacer()
                    Button(t("selectAll")) {
                        selectedRoles = Set(model.roles)
                    }
                    Button(t("selectNone")) {
                        selectedRoles = []
                    }
                }
                .disabled(model.roles.isEmpty)

                List(model.roles, id: \.self) { role in
                    HStack {
                        Toggle(isOn: roleSelection(role)) {
                            Text(role)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .toggleStyle(.checkbox)
                        Spacer(minLength: 12)
                        Text("\(model.roleCounts[role, default: 0]) \(t("lineCountSuffix"))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .frame(height: 240)
                .overlay {
                    if model.roles.isEmpty {
                        Text(t("roles.empty"))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(t("rolesSelectionHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// чекбокс роли: набор выбранных ролей нужен раздельному экспорту SRT
    private func roleSelection(_ role: String) -> Binding<Bool> {
        Binding(
            get: { selectedRoles.contains(role) },
            set: { isOn in
                if isOn {
                    selectedRoles.insert(role)
                } else {
                    selectedRoles.remove(role)
                }
            }
        )
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
                TextField(t("outputFolder"), text: $outputFolder)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .accessibilityLabel(t("outputFolder"))
                if !outputFolderExists {
                    Label(t("hint.badOutputFolder"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("\(t("source")): \(model.importedSubtitle?.sourceType.rawValue ?? t("notSelected"))")
                    .fontWeight(.semibold)
            }
        }
    }

    private var inputDropZone: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(inputPath.isEmpty ? t("dropHint") : inputPath)
                .lineLimit(3)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
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
        .dropDestination(for: URL.self) { urls, _ in
            handleDroppedFiles(urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .accessibilityLabel(t("inputFile"))
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

    private var srtPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("srtSettings"))
                    .font(.headline)
                Toggle(t("fullWithRoles"), isOn: $srtFullWithRoles)
                Toggle(t("separateByRole"), isOn: $srtSeparateFiles)
                Toggle(t("separateWithPrefix"), isOn: $srtSeparateWithRoles)
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
            selectedRoles = Set(model.roles)
        }
    }

    /// имена созданных файлов для алерта; длинный список сворачивается, иначе он не влезает на экран
    private var createdFilesSummary: String {
        let names: [String] = model.lastCreatedFiles.map { path in URL(fileURLWithPath: path).lastPathComponent }
        let shown: [String] = Array(names.prefix(10))
        let hidden: Int = names.count - shown.count
        if hidden <= 0 {
            return shown.joined(separator: "\n")
        }
        return (shown + [L.format("createdFilesMore", language, ["n": String(hidden)])]).joined(separator: "\n")
    }

    private func revealCreatedFiles() {
        let urls: [URL] = model.lastCreatedFiles.map { path in URL(fileURLWithPath: path) }
        if urls.isEmpty {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
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

    /// принимает перетащенный файл; при нескольких файлах берётся первый и об этом говорится вслух
    private func handleDroppedFiles(_ urls: [URL]) -> Bool {
        guard let first: URL = urls.first else {
            model.log(t("dropReadError"))
            return false
        }
        if urls.count > 1 {
            model.log(t("dropSingleFileOnly"))
        }
        inputPath = first.path
        reloadInput(path: first.path)
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
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw: String = AppLanguage.systemDefault.rawValue
    @Environment(\.openWindow) private var openWindow

    private var language: AppLanguage {
        AppLanguage.resolve(appLanguageRaw)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L.text("openSubtitles", language)) {
                NotificationCenter.default.post(name: .openSubtitleFile, object: nil)
            }
            .keyboardShortcut("o")
        }

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
        }
    }
}
