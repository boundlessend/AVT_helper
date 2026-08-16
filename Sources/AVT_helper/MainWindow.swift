import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage(LanguagePreference.storageKey) private var appLanguageRaw: String = LanguagePreference.system.rawValue
    @StateObject private var model: ProcessingModel = ProcessingModel()
    @StateObject private var options: ExportOptions = ExportOptions()
    @ObservedObject private var recent: RecentFiles = .shared
    @ObservedObject private var updates: UpdateController = .shared
    @State private var selectedRoles: Set<String> = []
    @State private var showDoneAlert: Bool = false
    @State private var showRoleAssignment: Bool = false
    @State private var showHistory: Bool = false
    @State private var isDropTargeted: Bool = false
    @State private var lastRun: ExportRun?

    private var language: AppLanguage {
        AppLanguage.resolve(appLanguageRaw)
    }

    private func t(_ key: String) -> String {
        L.text(key, language)
    }

    private var outputFolderExists: Bool {
        OutputFolder.isUsable(options.outputFolder)
    }

    /// причина, по которой запуск невозможен; nil означает, что всё готово
    private var startBlockReason: String? {
        if model.queue.isEmpty {
            return t("hint.selectInput")
        }
        if !options.hasFormat {
            return t("hint.selectFormat")
        }
        if !outputFolderExists {
            return t("hint.badOutputFolder")
        }
        return nil
    }

    /// причина, по которой разролёвка невозможна: ей нужен файл с ролями и живая папка выгрузки
    private var assignmentBlockReason: String? {
        if model.importedSubtitle == nil || model.digest.roles.isEmpty {
            return t("hint.selectInput")
        }
        if !outputFolderExists {
            return t("hint.badOutputFolder")
        }
        return nil
    }

    private var canStart: Bool {
        !model.isWorking && startBlockReason == nil
    }

    private var canAssign: Bool {
        !model.isWorking && assignmentBlockReason == nil
    }

    var body: some View {
        window
            .toolbar { toolbarContent }
            .navigationTitle(model.importedSubtitle?.baseName ?? "AVT_helper")
            .navigationSubtitle(windowSubtitle)
            .focusedSceneValue(\.windowActions, menuActions)
            .onReceive(NotificationCenter.default.publisher(for: .openSubtitleFiles), perform: handleOpenRequest)
            .onChange(of: appLanguageRaw) { _, _ in
                model.refreshDigest(language: language)
            }
            .task {
                await updates.checkIfDue(language: language)
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
                assignmentSheet
            }
    }

    private var window: some View {
        VStack(spacing: 0) {
            columns

            Divider()

            StatusBar(
                model: model,
                progress: model.progress,
                language: language,
                blockReason: startBlockReason,
                showHistory: $showHistory,
                onStart: runExport
            )
        }
    }

    /// колонки тянутся мышью: на узком окне реплике иначе достаётся меньше половины ширины
    private var columns: some View {
        HSplitView {
            ExportRailView(
                model: model,
                options: options,
                language: language,
                onChooseInput: chooseInputFiles,
                onChooseOutputFolder: chooseOutputFolder
            )
            .frame(minWidth: 214, idealWidth: 246, maxWidth: 340)
            .disabled(model.isWorking)

            sheetColumn
                .frame(minWidth: 360, maxWidth: .infinity)

            RolesColumn(
                digest: model.digest,
                highlights: model.roleHighlights,
                voices: model.roleVoices,
                language: language,
                selectedRoles: $selectedRoles,
                isUsed: options.srtSeparateFiles
            )
            .frame(minWidth: 224, idealWidth: 262, maxWidth: 400)
            .disabled(model.isWorking)
        }
    }

    private var menuActions: WindowActions {
        let start: (() -> Void)? = canStart ? { runExport() } : nil
        let assign: (() -> Void)? = canAssign ? { showRoleAssignment = true } : nil
        return WindowActions(start: start, assign: assign)
    }

    private func handleOpenRequest(_ notification: Notification) {
        if model.isWorking {
            return
        }
        if let urls: [URL] = notification.object as? [URL] {
            open(urls: urls)
        } else {
            chooseInputFiles()
        }
    }

    @ViewBuilder
    private var assignmentSheet: some View {
        if let subtitle: ImportedSubtitle = model.importedSubtitle {
            RoleAssignmentView(
                subtitle: subtitle,
                digest: model.digest,
                outputFolder: options.outputFolder,
                language: language,
                onComplete: { path, assignment in
                    model.acceptAssignment(path: path, assignment: assignment, language: language)
                    lastRun = ExportRun(created: [path], failed: 0)
                    showDoneAlert = true
                }
            )
            .frame(minWidth: 880, minHeight: 620)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                chooseInputFiles()
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
            .disabled(!canAssign)
            .help(assignmentBlockReason ?? t("makeRoleAssignment"))
        }
    }

    /// подзаголовок окна: состав файла держится в титуле, чтобы не занимать место в самом листе
    private var windowSubtitle: String {
        guard let subtitle: ImportedSubtitle = model.importedSubtitle else {
            return ""
        }
        let lines: String = L.plural("count.lines", language, subtitle.lines.count)
        let roles: String = L.plural("count.roles", language, model.digest.roles.count)
        let clock: String = TimeTools.formatClockSeconds(model.digest.duration)
        let queue: String = model.hasQueue ? " · " + L.plural("count.queuedFiles", language, model.queue.count) : ""
        return "\(lines) · \(roles) · \(subtitle.sourceType.rawValue) · \(clock)\(queue)"
    }

    /// центральная колонка: сам монтажный лист, он же зона перетаскивания
    private var sheetColumn: some View {
        Group {
            if let subtitle: ImportedSubtitle = model.importedSubtitle {
                SubtitleSheetView(subtitle: subtitle, language: language, highlights: model.roleHighlights)
            } else {
                SheetEmptyView(language: language, isDropTargeted: isDropTargeted, onOpen: chooseInputFiles)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(
            of: [.fileURL],
            delegate: SubtitleDropDelegate(
                isTargeted: $isDropTargeted,
                onDrop: { urls in open(urls: urls) }
            )
        )
        .accessibilityLabel(t("inputFile"))
    }

    private func chooseInputFiles() {
        let panel: NSOpenPanel = NSOpenPanel()
        // сезон открывают целиком: очередь всё равно обрабатывается одними настройками
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = SubtitleFormats.contentTypes
        if panel.runModal() == .OK {
            open(urls: panel.urls)
        }
    }

    private func chooseOutputFolder() {
        let panel: NSOpenPanel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url: URL = panel.url {
            options.outputFolder = url.path
            model.log("\(t("outputFolderLog")): \(url.path)")
        }
    }

    /// ставит файлы в очередь; чужие расширения отсеиваются здесь, а не падают ошибкой импорта
    private func open(urls: [URL]) {
        let accepted: [URL] = urls.filter(SubtitleFormats.accepts)
        if accepted.isEmpty {
            model.log(t("dropUnsupported"))
            return
        }
        if accepted.count < urls.count {
            model.log(t("dropUnsupported"))
        }
        Task {
            await model.enqueue(paths: accepted.map { url in url.path }, language: language)
            selectedRoles = Set(model.digest.roles)
            for url in accepted {
                recent.remember(url)
            }
        }
    }

    /// имена созданных файлов для алерта; длинный список сворачивается, иначе он не влезает на экран
    private var createdFilesSummary: String {
        guard let run: ExportRun = lastRun else {
            return ""
        }
        let names: [String] = run.created.map { path in URL(fileURLWithPath: path).lastPathComponent }
        let shown: [String] = Array(names.prefix(10))
        let hidden: Int = names.count - shown.count
        var parts: [String] = shown
        if hidden > 0 {
            parts.append(L.plural("count.moreFiles", language, hidden))
        }
        if run.failed > 0 {
            parts.append(L.format("done.failed", language, ["n": String(run.failed)]))
        }
        return parts.joined(separator: "\n")
    }

    private func revealCreatedFiles() {
        let urls: [URL] = (lastRun?.created ?? []).map { path in URL(fileURLWithPath: path) }
        if urls.isEmpty {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func runExport() {
        let settings: ExportSettings = options.settings(
            selectedRoles: selectedRoles,
            roleHighlights: model.roleHighlights
        )
        Task {
            guard
                let run: ExportRun = await model.exportQueue(
                    outputFolder: options.outputFolder,
                    settings: settings,
                    language: language
                )
            else {
                return
            }
            lastRun = run
            if !run.created.isEmpty {
                showDoneAlert = true
            }
        }
    }

    private func completeProcessing() {
        if options.openFolderAfter {
            NSWorkspace.shared.open(URL(fileURLWithPath: options.outputFolder))
        }
        if options.closeAppAfter {
            NSApp.terminate(nil)
        }
    }
}

// MARK: - перетаскивание

/// принимает только субтитры: подсветка зоны обещает, что файл возьмут,
/// и обещание нельзя давать файлу, который тут же отвергнут
struct SubtitleDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: @MainActor ([URL]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        accepts(info)
    }

    func dropEntered(info: DropInfo) {
        isTargeted = accepts(info)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let providers: [NSItemProvider] = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else {
            return false
        }
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url: URL = await loadURL(from: provider) {
                    urls.append(url)
                }
            }
            let collected: [URL] = urls
            await MainActor.run {
                onDrop(collected)
            }
        }
        return true
    }

    private func accepts(_ info: DropInfo) -> Bool {
        info.itemProviders(for: [.fileURL]).contains { provider in
            SubtitleFormats.accepts(name: provider.suggestedName ?? "")
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}

// MARK: - список ролей

/// правая колонка: роли файла, их доля и отметка для раздельных SRT
struct RolesColumn: View {
    let digest: SubtitleDigest
    let highlights: [String: WordHighlightColor]
    let voices: [String: Int]
    let language: AppLanguage
    @Binding var selectedRoles: Set<String>
    /// отметки нужны только раздельным файлам по ролям: без них колонка обещает выбор,
    /// который никуда не идёт
    let isUsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(text: L.plural("count.roles", language, digest.roles.count)) {
                Button(L.text("selectAll", language)) {
                    selectedRoles = Set(digest.roles)
                }
                Button(L.text("selectNone", language)) {
                    selectedRoles = []
                }
            }
            .controlSize(.small)
            .disabled(digest.roles.isEmpty || !isUsed)

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(digest.roles, id: \.self) { role in
                        RoleRow(
                            role: role,
                            count: digest.counts[role, default: 0],
                            share: digest.share(of: role),
                            color: highlights[role],
                            voice: voices[role],
                            isSelectable: isUsed,
                            language: language,
                            isSelected: selection(role)
                        )
                    }
                }
                .padding(.trailing, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if digest.roles.isEmpty {
                    Text(L.text("roles.empty", language))
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(L.text(isUsed ? "roles.colorHint" : "roles.colorHintIdle", language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// чекбокс роли: набор выбранных ролей нужен раздельному экспорту SRT
    private func selection(_ role: String) -> Binding<Bool> {
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
}

// MARK: - строка состояния

struct StatusBar: View {
    @ObservedObject var model: ProcessingModel
    @ObservedObject var progress: ProgressBox
    let language: AppLanguage
    /// причина, по которой запуск невозможен: она стоит рядом с кнопкой, а не прячется в подсказке
    let blockReason: String?
    @Binding var showHistory: Bool
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if model.isWorking {
                ProgressReadout(progress: progress)
                Button(L.text("cancel", language)) {
                    model.cancel()
                }
                .controlSize(.small)
            }

            Button {
                showHistory = true
            } label: {
                // без значка строка читается как обычный текст, и журнал за ней никто не откроет
                Label(model.status.isEmpty ? L.text("ready", language) : model.status, systemImage: "list.bullet.rectangle")
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.accessoryBar)
            .help(L.text("history.hint", language))
            .popover(isPresented: $showHistory, arrowEdge: .top) {
                HistoryPopover(history: model.history, language: language)
            }

            Spacer()

            if let reason: String = blockReason, !model.isWorking {
                Text(reason)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button(L.text("start", language)) {
                onStart()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.isWorking || blockReason != nil)
        }
        .font(.footnote)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// журнал сообщений: в строке состояния видно только последнее, а ошибка нужна и после следующего события
struct HistoryPopover: View {
    let history: [String]
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.text("history", language))
                .font(.headline)
            if history.isEmpty {
                Text(L.text("history.empty", language))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(history.enumerated().reversed()), id: \.offset) { item in
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
}
