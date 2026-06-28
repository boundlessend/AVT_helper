import Foundation

enum TimeTools {
    static func parseSrt(_ input: String) throws -> TimeInterval {
        try parseTime(input, separator: ",", allowShort: false)
    }

    static func parseVtt(_ input: String) throws -> TimeInterval {
        try parseTime(input, separator: ".", allowShort: true)
    }

    static func parseAss(_ input: String) throws -> TimeInterval {
        let normalized: String = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts: [String] = normalized.components(separatedBy: ".")
        guard parts.count == 2 else {
            throw SubtitleError.invalidTime(input)
        }
        let hms: [String] = parts[0].components(separatedBy: ":")
        guard hms.count == 3,
              let hours: Int = Int(hms[0]),
              let minutes: Int = Int(hms[1]),
              let seconds: Int = Int(hms[2]),
              let fraction: Int = Int(parts[1]) else {
            throw SubtitleError.invalidTime(input)
        }
        let milliseconds: Int = parts[1].count == 2 ? fraction * 10 : fraction
        return TimeInterval((hours * 3600 + minutes * 60 + seconds)) + TimeInterval(milliseconds) / 1000
    }

    static func formatSrt(_ input: TimeInterval) -> String {
        let parts: TimeParts = splitTime(input)
        return String(format: "%02d:%02d:%02d,%03d", parts.hours, parts.minutes, parts.seconds, parts.milliseconds)
    }

    static func formatAss(_ input: TimeInterval) -> String {
        let parts: TimeParts = splitTime(input)
        return String(format: "%d:%02d:%02d.%02d", parts.hours, parts.minutes, parts.seconds, parts.milliseconds / 10)
    }

    static func formatVtt(_ input: TimeInterval) -> String {
        let parts: TimeParts = splitTime(input)
        return String(format: "%02d:%02d:%02d.%03d", parts.hours, parts.minutes, parts.seconds, parts.milliseconds)
    }

    static func formatClockSeconds(_ input: TimeInterval) -> String {
        let parts: TimeParts = splitTime(input)
        if parts.hours > 0 {
            return String(format: "%d:%02d:%02d", parts.hours, parts.minutes, parts.seconds)
        }
        return String(format: "%02d:%02d", parts.minutes, parts.seconds)
    }

    private static func parseTime(_ input: String, separator: String, allowShort: Bool) throws -> TimeInterval {
        let normalized: String = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts: [String] = normalized.components(separatedBy: separator)
        guard parts.count == 2 else {
            throw SubtitleError.invalidTime(input)
        }

        let hms: [String] = parts[0].components(separatedBy: ":")
        let validCount: Bool = allowShort ? (hms.count == 2 || hms.count == 3) : hms.count == 3
        guard validCount, let fraction: Int = Int(parts[1]) else {
            throw SubtitleError.invalidTime(input)
        }

        let hours: Int
        let minutes: Int
        let seconds: Int
        if hms.count == 2 {
            guard let parsedMinutes: Int = Int(hms[0]), let parsedSeconds: Int = Int(hms[1]) else {
                throw SubtitleError.invalidTime(input)
            }
            hours = 0
            minutes = parsedMinutes
            seconds = parsedSeconds
        } else {
            guard let parsedHours: Int = Int(hms[0]),
                  let parsedMinutes: Int = Int(hms[1]),
                  let parsedSeconds: Int = Int(hms[2]) else {
                throw SubtitleError.invalidTime(input)
            }
            hours = parsedHours
            minutes = parsedMinutes
            seconds = parsedSeconds
        }

        let milliseconds: Int = parts[1].count == 2 ? fraction * 10 : fraction
        return TimeInterval((hours * 3600 + minutes * 60 + seconds)) + TimeInterval(milliseconds) / 1000
    }

    private static func splitTime(_ input: TimeInterval) -> TimeParts {
        let clamped: TimeInterval = max(0, input)
        let totalMilliseconds: Int = Int((clamped * 1000).rounded())
        let hours: Int = totalMilliseconds / 3_600_000
        let minutes: Int = (totalMilliseconds / 60_000) % 60
        let seconds: Int = (totalMilliseconds / 1000) % 60
        let milliseconds: Int = totalMilliseconds % 1000
        return TimeParts(hours: hours, minutes: minutes, seconds: seconds, milliseconds: milliseconds)
    }
}

struct TimeParts {
    let hours: Int
    let minutes: Int
    let seconds: Int
    let milliseconds: Int
}

enum SubtitleError: LocalizedError {
    case unsupportedFormat(String)
    case invalidTime(String)
    case importFailed(String)
    case exportFailed(String)

    /// сообщения локализуются по текущему языку приложения, прочитанному из настроек
    var errorDescription: String? {
        let language: AppLanguage = AppLanguage.current
        switch self {
        case .unsupportedFormat(let path):
            return "\(L.text("error.unsupportedFormat", language)): \(path)"
        case .invalidTime(let value):
            return "\(L.text("error.invalidTime", language)): \(value)"
        case .importFailed(let message):
            return "\(L.text("error.importPrefix", language)): \(message)"
        case .exportFailed(let message):
            return "\(L.text("error.exportPrefix", language)): \(message)"
        }
    }
}
