import Foundation

enum SubtitleError: Error {
    case unsupportedFormat(String)
    case invalidTime(String)
    /// сообщение уже локализовано в месте выброса
    case importFailed(String)
    case exportFailed(String)

    func message(_ language: AppLanguage) -> String {
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
