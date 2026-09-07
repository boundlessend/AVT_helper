import Foundation

enum SubtitleError: Error {
    case unsupportedFormat(String)
    case invalidTime(String)
    /// сообщение уже локализовано в месте выброса
    case importFailed(String)
    case exportFailed(String)
    /// свободного имени не нашлось за разумное число попыток: текст локализуется здесь,
    /// потому что место выброса про язык интерфейса не знает
    case tooManySimilarNames

    func message(_ language: AppLanguage) -> String {
        switch self {
        case .tooManySimilarNames:
            return L.format("error.exportPrefix", language, ["message": L.text("error.tooManySimilarNames", language)])
        case .unsupportedFormat(let path):
            return L.format("error.unsupportedFormat", language, ["path": path])
        case .invalidTime(let value):
            return L.format("error.invalidTime", language, ["value": value])
        case .importFailed(let message):
            return L.format("error.importPrefix", language, ["message": message])
        case .exportFailed(let message):
            return L.format("error.exportPrefix", language, ["message": message])
        }
    }
}
