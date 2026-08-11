import Foundation

/// клиент GitHub Releases для проверки наличия новой версии приложения
enum UpdateChecker {
    struct ReleaseInfo {
        let version: String
        let pageUrl: URL
    }

    private static let latestReleaseApi: String = "https://api.github.com/repos/boundlessend/AVT_helper/releases/latest"

    /// запрашивает последний опубликованный релиз и возвращает его версию и страницу загрузки
    static func fetchLatest() async throws -> ReleaseInfo {
        guard let url: URL = URL(string: latestReleaseApi) else {
            throw UpdateError.invalidResponse
        }
        var request: URLRequest = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response): (Data, URLResponse) = try await URLSession.shared.data(for: request)
        guard let http: HTTPURLResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw UpdateError.badStatus(http.statusCode)
        }
        let release: LatestRelease = try JSONDecoder().decode(LatestRelease.self, from: data)
        guard let pageUrl: URL = URL(string: release.htmlUrl) else {
            throw UpdateError.invalidResponse
        }
        return ReleaseInfo(version: normalizeTag(release.tagName), pageUrl: pageUrl)
    }

    /// убирает префикс "v." или "v" из имени тега: "v.1.6.5" -> "1.6.5"
    static func normalizeTag(_ tag: String) -> String {
        tag.replacingOccurrences(of: #"^v\.?"#, with: "", options: [.regularExpression])
    }

    /// сравнивает версии покомпонентно, иначе 1.10.0 считалось бы старше 1.9.9
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left: [Int] = numbers(candidate)
        let right: [Int] = numbers(current)
        for index in 0..<max(left.count, right.count) {
            let leftPart: Int = index < left.count ? left[index] : 0
            let rightPart: Int = index < right.count ? right[index] : 0
            if leftPart != rightPart {
                return leftPart > rightPart
            }
        }
        return false
    }

    private static func numbers(_ version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { part in Int(part.prefix { character in character.isNumber }) ?? 0 }
    }

    private struct LatestRelease: Decodable {
        let tagName: String
        let htmlUrl: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
        }
    }
}

enum UpdateError: Error {
    case badStatus(Int)
    case invalidResponse

    func message(_ language: AppLanguage) -> String {
        switch self {
        case .badStatus(let code):
            return L.format("error.updateFailed", language, ["code": String(code)])
        case .invalidResponse:
            return L.text("error.updateInvalidResponse", language)
        }
    }
}
