import Foundation

/// клиент GitHub Releases для проверки наличия новой версии приложения
enum UpdateChecker {
    struct ReleaseInfo: Sendable {
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
        // GitHub отдаёт 403 или 429 при исчерпании лимита запросов; счётчик остатка лежит в заголовке
        if http.statusCode == 403 || http.statusCode == 429, http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" {
            throw UpdateError.rateLimited
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

/// когда программа сама ходит на страницу релизов. проверка ничего не скачивает и не ставит:
/// она только сообщает, что версия вышла, и открывает браузер
@MainActor
final class UpdateController: ObservableObject {
    /// один на приложение: проверку зовут и меню, и окно «О программе», и запуск,
    /// а ходить в сеть трижды за одним ответом незачем
    static let shared: UpdateController = UpdateController()

    private enum Key {
        static let automatic: String = "checkUpdatesAutomatically"
        static let lastCheck: String = "lastUpdateCheck"
    }

    /// неделя: программой пользуются каждый день, а релизы выходят реже
    private static let interval: TimeInterval = 7 * 24 * 3600

    @Published private(set) var available: UpdateChecker.ReleaseInfo?
    @Published private(set) var isChecking: Bool = false
    @Published private(set) var message: String = ""
    @Published var automatic: Bool {
        didSet { defaults.set(automatic, forKey: Key.automatic) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automatic = defaults.object(forKey: Key.automatic) as? Bool ?? true
    }

    private var lastCheck: Date? {
        get { defaults.object(forKey: Key.lastCheck) as? Date }
        set { defaults.set(newValue, forKey: Key.lastCheck) }
    }

    /// фоновая проверка при запуске: молчит, если срок не вышел или её выключили
    func checkIfDue(language: AppLanguage) async {
        guard automatic else {
            return
        }
        if let last: Date = lastCheck, Date().timeIntervalSince(last) < Self.interval {
            return
        }
        await check(language: language, announceUpToDate: false)
    }

    /// проверка по нажатию: говорит и тогда, когда новой версии нет
    func checkNow(language: AppLanguage) async {
        await check(language: language, announceUpToDate: true)
    }

    private func check(language: AppLanguage, announceUpToDate: Bool) async {
        isChecking = true
        message = ""
        do {
            let release: UpdateChecker.ReleaseInfo = try await UpdateChecker.fetchLatest()
            lastCheck = Date()
            if UpdateChecker.isNewer(release.version, than: AppInfo.shortVersion) {
                available = release
                message = L.format("update.available", language, ["v": release.version])
            } else {
                available = nil
                message = announceUpToDate ? L.text("update.latest", language) : ""
            }
        } catch {
            available = nil
            message = announceUpToDate ? L.describe(error, language) : ""
        }
        isChecking = false
    }
}

enum UpdateError: Error {
    case badStatus(Int)
    case invalidResponse
    case rateLimited

    func message(_ language: AppLanguage) -> String {
        switch self {
        case .badStatus(let code):
            return L.format("error.updateFailed", language, ["code": String(code)])
        case .invalidResponse:
            return L.text("error.updateInvalidResponse", language)
        case .rateLimited:
            return L.text("error.updateRateLimited", language)
        }
    }
}
