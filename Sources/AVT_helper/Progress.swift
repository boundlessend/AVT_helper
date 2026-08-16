import Foundation

/// доля выполненной работы от 0 до 1; вызывается из фонового потока
typealias ProgressHandler = @Sendable (Double) -> Void

/// доля выполненной работы, которую видит интерфейс. проценты приходят из фоновой задачи
/// отдельными задачами, и порядок их доставки не гарантирован, поэтому полоска движется
/// только вперёд. Foundation.Progress сюда не годится: отмена уже живёт в дереве задач,
/// и вторая система отмены рядом с ней только запутала бы
@MainActor
final class ProgressBox: ObservableObject {
    @Published private(set) var value: Double = 0

    func reset() {
        value = 0
    }

    /// обработчик для фоновой работы; ссылка слабая, чтобы задача не держала интерфейс
    nonisolated func handler(scale: Double, offset: Double) -> ProgressHandler {
        { [weak self] fraction in
            let scaled: Double = offset + fraction * scale
            Task { @MainActor in
                self?.advance(to: scaled)
            }
        }
    }

    private func advance(to fraction: Double) {
        if fraction > value {
            value = fraction
        }
    }
}

/// считает единицы работы долгой операции: сообщает прогресс не чаще раза на процент и проверяет отмену
struct ProgressCounter {
    private let total: Int
    private let report: ProgressHandler
    private var done: Int = 0
    private var lastPercent: Int = -1

    init(total: Int, report: @escaping ProgressHandler) {
        self.total = max(total, 1)
        self.report = report
    }

    /// отмечает выполненную единицу работы; бросает CancellationError, если операцию отменили
    mutating func step() throws {
        try Task.checkCancellation()
        done += 1
        let percent: Int = done * 100 / total
        if percent != lastPercent {
            lastPercent = percent
            report(Double(done) / Double(total))
        }
    }
}
