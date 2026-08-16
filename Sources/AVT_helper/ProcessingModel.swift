import Foundation

/// что стало с файлом очереди после прогона
enum QueueItemState: Equatable, Sendable {
    case waiting
    case done(Int)
    case failed(String)
}

/// файл, поставленный в очередь. в памяти держится только путь: разбирать сезон целиком
/// заранее незачем, реплики нужны либо показанному файлу, либо тому, что прямо сейчас пишется
struct QueuedFile: Identifiable, Sendable {
    let id: UUID
    let path: String
    var state: QueueItemState

    init(path: String) {
        id = UUID()
        self.path = path
        state = .waiting
    }

    var name: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

/// результат прогона очереди: он же то, что показывают в алерте по окончании
struct ExportRun: Sendable {
    let created: [String]
    let failed: Int
}

/// держит очередь файлов и выполняет тяжёлые импорт и экспорт вне главного потока
@MainActor
final class ProcessingModel: ObservableObject {
    @Published private(set) var queue: [QueuedFile] = []
    @Published private(set) var selectedFileID: QueuedFile.ID?
    /// разобранный файл, который показывает монтажный лист
    @Published private(set) var importedSubtitle: ImportedSubtitle?
    /// роли, счётчики и хронометраж показанного файла
    @Published private(set) var digest: SubtitleDigest = .empty
    /// цвет маркера для каждой роли: после импорта автоматический, после разролёвки - цвет назначенного голоса
    @Published var roleHighlights: [String: WordHighlightColor] = [:]
    /// голос каждой роли после разролёвки: цвет один на голос, поэтому номер нужен, чтобы их различать
    @Published var roleVoices: [String: Int] = [:]
    @Published var status: String = ""
    @Published private(set) var isWorking: Bool = false
    /// отдельный объект, а не поле: тот же счётчик нужен листу разролёвки,
    /// и правило «полоска движется только вперёд» должно жить в одном месте
    let progress: ProgressBox = ProgressBox()
    /// последние сообщения статуса: без журнала ошибка исчезает под следующим же событием
    @Published private(set) var history: [String] = []

    private var cancelCurrentWork: (() -> Void)?
    /// система вправе убить простаивающую программу при выходе из учётной записи,
    /// но не посреди записи файлов: на время работы запрет включается и снимается парой
    private var isHoldingTermination: Bool = false

    var selectedFile: QueuedFile? {
        queue.first { file in file.id == selectedFileID }
    }

    var hasQueue: Bool {
        queue.count > 1
    }

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

    // MARK: - очередь

    /// ставит файлы в очередь и показывает первый новый. повтор не задваивается,
    /// а поднимает уже стоящий файл на экран
    func enqueue(paths: [String], language: AppLanguage) async {
        var firstAdded: QueuedFile.ID?
        for path in paths {
            let standardized: String = URL(fileURLWithPath: path).standardizedFileURL.path
            if let existing: QueuedFile = queue.first(where: { file in file.path == standardized }) {
                firstAdded = firstAdded ?? existing.id
                continue
            }
            let file: QueuedFile = QueuedFile(path: standardized)
            queue.append(file)
            firstAdded = firstAdded ?? file.id
        }
        guard let target: QueuedFile.ID = firstAdded else {
            return
        }
        await select(target, language: language)
    }

    func select(_ id: QueuedFile.ID, language: AppLanguage) async {
        guard let file: QueuedFile = queue.first(where: { item in item.id == id }) else {
            return
        }
        selectedFileID = id
        await loadSelected(path: file.path, language: language)
    }

    /// убирает файл из очереди; показанным становится соседний, а пустая очередь очищает лист
    func remove(_ id: QueuedFile.ID, language: AppLanguage) async {
        guard let index: Int = queue.firstIndex(where: { file in file.id == id }) else {
            return
        }
        queue.remove(at: index)
        guard selectedFileID == id else {
            return
        }
        guard let next: QueuedFile = queue.indices.contains(index) ? queue[index] : queue.last else {
            selectedFileID = nil
            forgetInput()
            return
        }
        await select(next.id, language: language)
    }

    func clearQueue() {
        queue = []
        selectedFileID = nil
        forgetInput()
    }

    /// сбрасывает пометки прошлого прогона: очередь остаётся, но она снова вся ожидающая
    private func resetQueueStates() {
        for index in queue.indices {
            queue[index].state = .waiting
        }
    }

    // MARK: - импорт

    private func loadSelected(path: String, language: AppLanguage) async {
        beginWork()
        let report: ProgressHandler = progress.handler(scale: 1, offset: 0)
        let work: Task<ImportedSubtitle, Error> = Task.detached(priority: .userInitiated) {
            try SubtitleImporter.importFile(path: path, language: language, progress: report)
        }
        cancelCurrentWork = { work.cancel() }
        do {
            let imported: ImportedSubtitle = try await work.value
            apply(imported: imported, language: language)
            log(L.plural("count.lines", language, imported.lines.count) + ", \(imported.sourceType.rawValue)")
        } catch {
            // прежний файл остаётся на экране: отменённый импорт не повод терять работу,
            // а неудачный файл уходит из очереди, чтобы не мешал прогону
            queue.removeAll { file in file.path == path }
            selectedFileID = importedSubtitle == nil ? nil : selectedFileID
            log(L.describe(error, language))
        }
        finishWork()
    }

    private func apply(imported: ImportedSubtitle, language: AppLanguage) {
        importedSubtitle = imported
        digest = SubtitleDigest(subtitle: imported, language: language)
        roleHighlights = RoleColors.automatic(roles: digest.roles, placeholder: digest.placeholder)
        roleVoices = [:]
    }

    /// перечитывает показанный файл на другом языке: метка нераспознанной роли живёт в дайджесте
    func refreshDigest(language: AppLanguage) {
        guard let subtitle: ImportedSubtitle = importedSubtitle else {
            return
        }
        apply(imported: subtitle, language: language)
    }

    // MARK: - экспорт

    /// прогоняет всю очередь одними настройками. отметки ролей принадлежат показанному файлу,
    /// у остальных свои роли, поэтому им идут все
    func exportQueue(outputFolder: String, settings: ExportSettings, language: AppLanguage) async -> ExportRun? {
        guard !queue.isEmpty else {
            log(SubtitleError.exportFailed(L.text("error.noInputSelected", language)).message(language))
            return nil
        }
        beginWork()
        resetQueueStates()

        let items: [QueuedFile] = queue
        let selectedPath: String? = selectedFile?.path
        let preloaded: ImportedSubtitle? = importedSubtitle
        let box: ProgressBox = progress

        let work: Task<[(QueuedFile.ID, QueueItemState, [String])], Error> = Task.detached(priority: .userInitiated) {
            var results: [(QueuedFile.ID, QueueItemState, [String])] = []
            for (index, item) in items.enumerated() {
                try Task.checkCancellation()
                let base: Double = Double(index) / Double(items.count)
                let span: Double = 1 / Double(items.count)
                do {
                    let subtitle: ImportedSubtitle
                    if item.path == selectedPath, let preloaded: ImportedSubtitle = preloaded {
                        subtitle = preloaded
                    } else {
                        subtitle = try SubtitleImporter.importFile(path: item.path, language: language)
                    }
                    let digest: SubtitleDigest = SubtitleDigest(subtitle: subtitle, language: language)
                    // у соседней серии свои роли, поэтому и отметки, и цвета берутся её собственные
                    let effective: ExportSettings =
                        item.path == selectedPath
                        ? settings
                        : settings.forOtherFile(
                            roles: Set(digest.roles),
                            highlights: RoleColors.automatic(roles: digest.roles, placeholder: digest.placeholder)
                        )
                    let created: [String] = try SubtitleExporter.export(
                        subtitle: subtitle,
                        outputFolder: outputFolder,
                        settings: effective,
                        digest: digest,
                        language: language,
                        progress: box.handler(scale: span, offset: base)
                    )
                    results.append((item.id, .done(created.count), created))
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as PartialExportError {
                    results.append((item.id, .failed(L.describe(error, language)), error.created))
                } catch {
                    results.append((item.id, .failed(L.describe(error, language)), []))
                }
            }
            return results
        }
        cancelCurrentWork = { work.cancel() }

        var run: ExportRun?
        do {
            let results: [(QueuedFile.ID, QueueItemState, [String])] = try await work.value
            var created: [String] = []
            var failed: Int = 0
            for (id, state, paths) in results {
                if let index: Int = queue.firstIndex(where: { file in file.id == id }) {
                    queue[index].state = state
                }
                created += paths
                if case .failed(let message) = state {
                    failed += 1
                    log(message)
                }
            }
            run = ExportRun(created: created, failed: failed)
            log(
                "\(L.text("ready", language)). \(L.text("createdFiles", language)): "
                    + L.plural("count.files", language, created.count))
        } catch {
            log(L.describe(error, language))
        }
        finishWork()
        return run
    }

    /// разролёвка кладёт готовый файл сама: модели остаётся запомнить его и раскрасить лист
    func acceptAssignment(path: String, assignment: RoleAssignmentResult, language: AppLanguage) {
        roleHighlights = assignment.roleToHighlight
        roleVoices = assignment.roleToVoice
        log("\(L.text("createdAssignment", language)): \(URL(fileURLWithPath: path).lastPathComponent)")
    }

    private func forgetInput() {
        importedSubtitle = nil
        digest = .empty
        roleHighlights = [:]
        roleVoices = [:]
    }

    private func beginWork() {
        isWorking = true
        progress.reset()
        if !isHoldingTermination {
            ProcessInfo.processInfo.disableSuddenTermination()
            isHoldingTermination = true
        }
    }

    private func finishWork() {
        cancelCurrentWork = nil
        isWorking = false
        progress.reset()
        if isHoldingTermination {
            ProcessInfo.processInfo.enableSuddenTermination()
            isHoldingTermination = false
        }
    }
}
