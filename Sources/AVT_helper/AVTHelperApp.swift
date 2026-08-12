import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct AVTHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1000, minHeight: 640)
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
    /// цвет маркера для каждой роли: после импорта автоматический, после разролёвки - цвет назначенного голоса
    @Published var roleHighlights: [String: WordHighlightColor] = [:]
    /// хронометраж файла, посчитанный один раз при импорте
    @Published var duration: TimeInterval = 0
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
            roleHighlights = RoleColors.automatic(roles: roles)
            duration = imported.lines.map { line in line.end }.max() ?? 0
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
        roleHighlights = [:]
        duration = 0
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

    private var outputFolderExists: Bool {
        OutputFolder.isUsable(outputFolder)
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

    /// причина, по которой разролёвка невозможна: ей нужен файл с ролями и живая папка выгрузки
    private var assignmentBlockReason: String? {
        if model.importedSubtitle == nil || model.roles.isEmpty {
            return t("hint.selectInput")
        }
        if !outputFolderExists {
            return t("hint.badOutputFolder")
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                rail
                Divider()
                sheetColumn
                Divider()
                rolesColumn
            }
            Divider()
            statusBar
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    chooseInputFile()
                } label: {
                    Label(t("openSubtitles"), systemImage: "doc.badge.plus")
                }
                .disabled(model.isWorking)
                .help(t("openSubtitles"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showRoleAssignment = true
                } label: {
                    Label(t("makeRoleAssignment"), systemImage: "person.2")
                }
                .disabled(model.isWorking || assignmentBlockReason != nil)
                .help(assignmentBlockReason ?? t("makeRoleAssignment"))
            }
        }
        .navigationTitle(model.importedSubtitle?.baseName ?? "AVT_helper")
        .navigationSubtitle(windowSubtitle)
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
                    onComplete: { path, highlights in
                        model.lastCreatedFiles = [path]
                        model.roleHighlights = highlights
                        model.log("\(t("createdAssignment")): \(path)")
                        showDoneAlert = true
                    }
                )
                .frame(minWidth: 880, minHeight: 620)
            }
        }
    }

    /// подзаголовок окна: состав файла держится в титуле, чтобы не занимать место в самом листе
    private var windowSubtitle: String {
        guard let subtitle: ImportedSubtitle = model.importedSubtitle else {
            return ""
        }
        let lines: String = "\(subtitle.lines.count) \(t("lines"))"
        let roles: String = "\(model.roles.count) \(t("rolesCountSuffix"))"
        return "\(lines) · \(roles) · \(subtitle.sourceType.rawValue) · \(TimeTools.formatClockSeconds(model.duration))"
    }

    /// левый рельс: всё, что задаёт выгрузку, собрано в одном столбце и не спорит с листом за внимание
    private var rail: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                sourceSection
                outputSection
                formatsSection
                srtSection
                afterSection
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 238)
        .background(Color(nsColor: .windowBackgroundColor))
        .disabled(model.isWorking)
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: t("source"))
            Button {
                chooseInputFile()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.importedSubtitle.map { subtitle in subtitle.baseName } ?? t("notSelected"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(model.importedSubtitle == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    if let subtitle: ImportedSubtitle = model.importedSubtitle {
                        Text("\(subtitle.sourceType.rawValue) · \(subtitle.lines.count) \(t("lines"))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .help(t("openSubtitles"))
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: t("outputFolder"))
            HStack(spacing: 6) {
                TextField(t("outputFolder"), text: $outputFolder)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .font(.system(size: 11, design: .monospaced))
                    .accessibilityLabel(t("outputFolder"))
                Button {
                    chooseOutputFolder()
                } label: {
                    Image(systemName: "folder")
                }
                .help(t("chooseOutputFolder"))
            }
            if !outputFolderExists {
                Label(t("hint.badOutputFolder"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var formatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: t("export"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                FormatToggle(title: "SRT", isOn: $exportSrt)
                FormatToggle(title: "DOCX", isOn: $exportDocx)
                FormatToggle(title: "ASS", isOn: $exportAss)
                FormatToggle(title: "VTT", isOn: $exportVtt)
            }
        }
    }

    private var srtSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: t("srtSettings"))
            VStack(alignment: .leading, spacing: 7) {
                Toggle(t("fullWithRoles"), isOn: $srtFullWithRoles)
                Toggle(t("separateByRole"), isOn: $srtSeparateFiles)
                Toggle(t("separateWithPrefix"), isOn: $srtSeparateWithRoles)
            }
            .font(.system(size: 12))
        }
    }

    private var afterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: t("afterProcessing"))
            VStack(alignment: .leading, spacing: 7) {
                Toggle(t("openFolderAfter"), isOn: $openFolderAfterProcessing)
                Toggle(t("closeAppAfter"), isOn: $closeProgramAfterProcessing)
            }
            .font(.system(size: 12))
        }
    }

    /// центральная колонка: сам монтажный лист, он же зона перетаскивания
    private var sheetColumn: some View {
        Group {
            if let subtitle: ImportedSubtitle = model.importedSubtitle {
                SubtitleSheetView(subtitle: subtitle, language: language, highlights: model.roleHighlights)
            } else {
                SheetEmptyView(language: language, isDropTargeted: isDropTargeted, onOpen: chooseInputFile)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            handleDroppedFiles(urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .accessibilityLabel(t("inputFile"))
    }

    private var rolesColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "\(t("roles")) · \(model.roles.count)")
                Spacer()
                Button(t("selectAll")) {
                    selectedRoles = Set(model.roles)
                }
                Button(t("selectNone")) {
                    selectedRoles = []
                }
            }
            .controlSize(.small)
            .disabled(model.roles.isEmpty)

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(model.roles, id: \.self) { role in
                        RoleRow(
                            role: role,
                            count: model.roleCounts[role, default: 0],
                            share: roleShare(role),
                            color: model.roleHighlights[role],
                            language: language,
                            isSelected: roleSelection(role)
                        )
                    }
                }
                .padding(.trailing, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if model.roles.isEmpty {
                    Text(t("roles.empty"))
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(t("roles.colorHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 262)
        .background(Color(nsColor: .windowBackgroundColor))
        .disabled(model.isWorking)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if model.isWorking {
                ProgressView(value: model.progress)
                    .frame(width: 120)
                Text("\(Int(model.progress * 100))%")
                    .monospacedDigit()
                Button(t("cancel")) {
                    model.cancel()
                }
                .controlSize(.small)
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
                .foregroundStyle(.tertiary)
            Button(t("start")) {
                runExport()
            }
            .keyboardShortcut(.return)
            .disabled(model.isWorking || startBlockReason != nil)
            .help(startBlockReason ?? t("start"))
        }
        .font(.footnote)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// доля реплик роли от всего файла: она же длина полоски в списке ролей
    private func roleShare(_ role: String) -> Double {
        let total: Int = model.importedSubtitle?.lines.count ?? 0
        if total == 0 {
            return 0
        }
        return Double(model.roleCounts[role, default: 0]) / Double(total)
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

    private func chooseInputFile() {
        let panel: NSOpenPanel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["ass", "ssa", "srt", "vtt", "srp"].compactMap { ext in
            UTType(filenameExtension: ext)
        }
        if panel.runModal() == .OK, let url: URL = panel.url {
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
