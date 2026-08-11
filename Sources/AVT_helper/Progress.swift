import Foundation

/// доля выполненной работы от 0 до 1; вызывается из фонового потока
typealias ProgressHandler = @Sendable (Double) -> Void

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
