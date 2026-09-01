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

/// что прогон успел сделать с одним файлом очереди
private struct QueueItemOutcome: Sendable {
    let id: QueuedFile.ID
    let state: QueueItemState
    let created: [String]
}

/// итог фонового прогона: отмена возвращает уже накопленное, а не теряет его вместе с брошенной ошибкой
private struct QueueRunOutcome: Sendable {
    let items: [QueueItemOutcome]
    let cancelled: Bool
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
        // дайджест считается там же, где идёт разбор: на главном потоке это лишние проходы по всем репликам
        let work: Task<(ImportedSubtitle, SubtitleDigest), Error> = Task.detached(priority: .userInitiated) {
            let imported: ImportedSubtitle = try SubtitleImporter.importFile(path: path, language: language, progress: report)
            return (imported, SubtitleDigest(subtitle: imported, language: language))
        }
        cancelCurrentWork = { work.cancel() }
        do {
            let (imported, computed): (ImportedSubtitle, SubtitleDigest) = try await work.value
            apply(imported: imported, digest: computed)
            // непрочитанные блоки называются числом: молча потерянная часть файла
            // выглядит как файл, в котором этих реплик и не было
            let skipped: String =
                imported.skippedBlocks == 0
                ? ""
                : ", " + L.format("import.skipped", language, ["n": L.plural("count.blocks", language, imported.skippedBlocks)])
            log(L.plural("count.lines", language, imported.lines.count) + ", \(imported.sourceType.rawValue)" + skipped)
        } catch let cancellation as CancellationError {
            // отменил пользователь: файл остаётся в очереди, а на экране остаётся прежний
            log(L.describe(cancellation, language))
        } catch {
            // неудачный файл уходит из очереди, чтобы не мешал прогону, а показанным снова числится тот,
            // который на самом деле разобран
            queue.removeAll { file in file.path == path }
            selectedFileID = queue.first { file in file.path == importedSubtitle?.sourcePath }?.id
            log(L.describe(error, language))
        }
        finishWork()
    }

    private func apply(imported: ImportedSubtitle, digest computed: SubtitleDigest) {
        importedSubtitle = imported
        digest = computed
        roleHighlights = RoleColors.automatic(roles: computed.roles, placeholder: computed.placeholder)
        roleVoices = [:]
    }

    /// перечитывает показанный файл на другом языке: метка нераспознанной роли живёт в дайджесте.
    /// готовая разролёвка при этом остаётся: язык интерфейса к назначенным голосам отношения не имеет,
    /// а переименовывается только сама метка
    func refreshDigest(language: AppLanguage) {
        guard let subtitle: ImportedSubtitle = importedSubtitle else {
            return
        }
        let previousPlaceholder: String? = digest.placeholder
        let computed: SubtitleDigest = SubtitleDigest(subtitle: subtitle, language: language)
        digest = computed
        if roleVoices.isEmpty {
            roleHighlights = RoleColors.automatic(roles: computed.roles, placeholder: computed.placeholder)
            return
        }
        roleVoices = renamedPlaceholder(in: roleVoices, from: previousPlaceholder, to: computed.placeholder)
        roleHighlights = renamedPlaceholder(in: roleHighlights, from: previousPlaceholder, to: computed.placeholder)
    }

    /// метка нераспознанной роли это подставленный текст, а не имя из файла: при смене языка
    /// она меняется, и назначенное ей значение надо перенести на новое написание
    private func renamedPlaceholder<Value>(in map: [String: Value], from old: String?, to new: String?) -> [String: Value] {
        guard let old: String = old, let new: String = new, old != new, let value: Value = map[old] else {
            return map
        }
        var result: [String: Value] = map
        result.removeValue(forKey: old)
        result[new] = value
        return result
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

        let work: Task<QueueRunOutcome, Never> = Task.detached(priority: .userInitiated) {
            var results: [QueueItemOutcome] = []
            for (index, item) in items.enumerated() {
                if Task.isCancelled {
                    return QueueRunOutcome(items: results, cancelled: true)
                }
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
                    results.append(QueueItemOutcome(id: item.id, state: .done(created.count), created: created))
                } catch is CancellationError {
                    // уже сделанное не пропадает вместе с отменой: оно уходит наверх вместе с признаком
                    return QueueRunOutcome(items: results, cancelled: true)
                } catch let error as PartialExportError {
                    results.append(QueueItemOutcome(id: item.id, state: .failed(L.describe(error, language)), created: error.created))
                } catch {
                    results.append(QueueItemOutcome(id: item.id, state: .failed(L.describe(error, language)), created: []))
                }
            }
            return QueueRunOutcome(items: results, cancelled: false)
        }
        cancelCurrentWork = { work.cancel() }

        let outcome: QueueRunOutcome = await work.value
        var created: [String] = []
        var failed: Int = 0
        for item in outcome.items {
            if let index: Int = queue.firstIndex(where: { file in file.id == item.id }) {
                queue[index].state = item.state
            }
            created += item.created
            if case .failed(let message) = item.state {
                failed += 1
                log(message)
            }
        }
        if outcome.cancelled {
            log(L.text("cancelled", language))
        }
        log(L.format("done.summary", language, ["files": L.plural("count.files", language, created.count)]))
        finishWork()
        return ExportRun(created: created, failed: failed)
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
        // выход и закрытие последнего окна спрашивают подтверждение по этому флагу:
        // сама модель про меню «Завершить» не знает, а знать о работе должен именно тот, кто пишет
        WorkGuard.isBusy = true
        progress.reset()
        if !isHoldingTermination {
            ProcessInfo.processInfo.disableSuddenTermination()
            isHoldingTermination = true
        }
    }

    private func finishWork() {
        cancelCurrentWork = nil
        isWorking = false
        WorkGuard.isBusy = false
        progress.reset()
        if isHoldingTermination {
            ProcessInfo.processInfo.enableSuddenTermination()
            isHoldingTermination = false
        }
    }
}
