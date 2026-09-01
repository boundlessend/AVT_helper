import Foundation

enum TimeTools {
    /// верхний предел на часы: больше любого фильма, при этом hours * 3600 заведомо не переполняет Int
    private static let maxHours: Int = 1000
    private static let maxSeconds: Int = maxHours * 3600

    /// разбирает таймкод SRT, допуская точку как разделитель миллисекунд в нестрогих файлах
    static func parseSrt(_ input: String) throws -> TimeInterval {
        try parseTime(input.replacingOccurrences(of: ".", with: ","), separator: ",", allowShort: false)
    }

    static func parseVtt(_ input: String) throws -> TimeInterval {
        try parseTime(input, separator: ".", allowShort: true)
    }

    /// в ASS разделитель долей секунды точка, но встречается и запятая
    static func parseAss(_ input: String) throws -> TimeInterval {
        try parseTime(input.replacingOccurrences(of: ",", with: "."), separator: ".", allowShort: false)
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
        guard validCount else {
            throw SubtitleError.invalidTime(input)
        }

        let hours: Int
        let minutes: Int
        let seconds: Int
        if hms.count == 2 {
            hours = 0
            minutes = try component(hms[0], limit: maxSeconds, input: input)
            seconds = try component(hms[1], limit: maxSeconds, input: input)
        } else {
            hours = try component(hms[0], limit: maxHours, input: input)
            minutes = try component(hms[1], limit: maxSeconds, input: input)
            seconds = try component(hms[2], limit: maxSeconds, input: input)
        }

        let milliseconds: Int = try fractionMilliseconds(parts[1])
        return TimeInterval((hours * 3600 + minutes * 60 + seconds)) + TimeInterval(milliseconds) / 1000
    }

    /// компонент таймкода состоит только из цифр и не выходит за предел: Int("-1") разобрался бы успешно
    /// и дал отрицательное время, а часы в шестнадцать знаков роняли бы процесс на переполнении
    private static func component(_ raw: String, limit: Int, input: String) throws -> Int {
        guard !raw.isEmpty, isAsciiDigits(raw), let value: Int = Int(raw), value <= limit else {
            throw SubtitleError.invalidTime(input)
        }
        return value
    }

    /// переводит долю секунды в миллисекунды с учётом числа цифр: "5" -> 500, "50" -> 500, "500" -> 500
    private static func fractionMilliseconds(_ raw: String) throws -> Int {
        let digits: String = String(raw.prefix(3))
        guard !digits.isEmpty, isAsciiDigits(digits), let value: Int = Int(digits) else {
            throw SubtitleError.invalidTime(raw)
        }
        switch digits.count {
        case 1:
            return value * 100
        case 2:
            return value * 10
        default:
            return value
        }
    }

    private static func isAsciiDigits(_ raw: String) -> Bool {
        raw.allSatisfy { character in character.isASCII && character.isNumber }
    }

    private static func splitTime(_ input: TimeInterval) -> TimeParts {
        // зажимаем и сверху: перевод слишком большого значения в Int - это trap, а не ошибка, его не поймать через try?
        let clamped: TimeInterval = min(max(0, input), TimeInterval(maxSeconds))
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
