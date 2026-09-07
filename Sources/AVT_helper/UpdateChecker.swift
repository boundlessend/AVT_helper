import Foundation
import Observation

/// клиент GitHub Releases для проверки наличия новой версии приложения
enum UpdateChecker {
    struct ReleaseInfo: Sendable {
        let version: String
        let pageUrl: URL
    }

    /// ответ на условный запрос: сервер либо присылает релиз, либо подтверждает, что он не менялся
    enum FetchResult: Sendable {
        case release(ReleaseInfo, etag: String?)
        case notModified
    }

    private static let latestReleaseApi: String = "https://api.github.com/repos/boundlessend/AVT_helper/releases/latest"

    /// запрашивает последний опубликованный релиз и возвращает его версию и страницу загрузки.
    /// etag прошлого ответа бережёт лимит в 60 запросов на адрес: на неизменившийся релиз GitHub отвечает 304 без тела
    static func fetchLatest(etag: String?) async throws -> FetchResult {
        guard let url: URL = URL(string: latestReleaseApi) else {
            throw UpdateError.invalidResponse
        }
        var request: URLRequest = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("AVT_helper/\(AppInfo.shortVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        if let etag: String = etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response): (Data, URLResponse) = try await URLSession.shared.data(for: request)
        guard let http: HTTPURLResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }
        if http.statusCode == 304 {
            return .notModified
        }
        let remaining: String? = http.value(forHTTPHeaderField: "x-ratelimit-remaining")
        let retryAfter: String? = http.value(forHTTPHeaderField: "retry-after")
        // основной лимит отдаёт 403 или 429 со счётчиком остатка, вторичный - без счётчика, зато с retry-after
        if http.statusCode == 403 || http.statusCode == 429, remaining == "0" || retryAfter != nil {
            throw UpdateError.rateLimited
        }
        guard http.statusCode == 200 else {
            throw UpdateError.badStatus(http.statusCode)
        }
        let decoder: JSONDecoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release: LatestRelease = try decoder.decode(LatestRelease.self, from: data)
        let pageUrl: URL = try releasePageUrl(release.htmlUrl)
        let info: ReleaseInfo = ReleaseInfo(version: normalizeTag(release.tagName), pageUrl: pageUrl)
        return .release(info, etag: http.value(forHTTPHeaderField: "Etag"))
    }

    /// адрес приходит из сети, а NSWorkspace открывает любую схему, включая file:// и чужие зарегистрированные,
    /// поэтому наружу уходит только https на github.com или его поддомен
    private static func releasePageUrl(_ raw: String) throws -> URL {
        guard let url: URL = URL(string: raw),
            url.scheme?.lowercased() == "https",
            let host: String = url.host()?.lowercased(),
            host == "github.com" || host.hasSuffix(".github.com")
        else {
            throw UpdateError.invalidResponse
        }
        return url
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
    }
}

/// когда программа сама ходит на страницу релизов. проверка ничего не скачивает и не ставит:
/// она только сообщает, что версия вышла, и открывает браузер
@MainActor
@Observable
final class UpdateController {
    /// один на приложение: проверку зовут и меню, и окно «О программе», и запуск,
    /// а ходить в сеть трижды за одним ответом незачем
    static let shared: UpdateController = UpdateController()

    private enum Key {
        static let automatic: String = "checkUpdatesAutomatically"
        static let lastCheck: String = "lastUpdateCheck"
        static let lastCheckFailed: String = "lastUpdateCheckFailed"
        static let etag: String = "lastUpdateEtag"
        static let knownVersion: String = "lastUpdateKnownVersion"
        static let knownPage: String = "lastUpdateKnownPage"
    }

    /// неделя: программой пользуются каждый день, а релизы выходят реже
    private static let interval: TimeInterval = 7 * 24 * 3600

    /// час после неудачи: иначе единственный обрыв сети отодвигает следующую попытку на неделю
    private static let retryInterval: TimeInterval = 3600

    private(set) var available: UpdateChecker.ReleaseInfo?
    private(set) var isChecking: Bool = false
    private(set) var message: String = ""
    var automatic: Bool {
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

    private var lastCheckFailed: Bool {
        get { defaults.bool(forKey: Key.lastCheckFailed) }
        set { defaults.set(newValue, forKey: Key.lastCheckFailed) }
    }

    /// разобранный ответ прошлой проверки: на 304 сервер тела не присылает, а решать о новизне всё равно надо
    private var known: (etag: String, release: UpdateChecker.ReleaseInfo)? {
        guard let etag: String = defaults.string(forKey: Key.etag),
            let version: String = defaults.string(forKey: Key.knownVersion),
            let page: String = defaults.string(forKey: Key.knownPage),
            let pageUrl: URL = URL(string: page)
        else {
            return nil
        }
        return (etag, UpdateChecker.ReleaseInfo(version: version, pageUrl: pageUrl))
    }

    private func remember(etag: String?, release: UpdateChecker.ReleaseInfo) {
        if let etag: String = etag {
            defaults.set(etag, forKey: Key.etag)
        } else {
            defaults.removeObject(forKey: Key.etag)
        }
        defaults.set(release.version, forKey: Key.knownVersion)
        defaults.set(release.pageUrl.absoluteString, forKey: Key.knownPage)
    }

    /// фоновая проверка при запуске: молчит, если срок не вышел или её выключили
    func checkIfDue(language: AppLanguage) async {
        guard automatic else {
            return
        }
        let due: TimeInterval = lastCheckFailed ? Self.retryInterval : Self.interval
        if let last: Date = lastCheck, Date().timeIntervalSince(last) < due {
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
        let previous: (etag: String, release: UpdateChecker.ReleaseInfo)? = known
        do {
            let release: UpdateChecker.ReleaseInfo = try await fetched(previous: previous)
            lastCheck = Date()
            lastCheckFailed = false
            if UpdateChecker.isNewer(release.version, than: AppInfo.shortVersion) {
                available = release
                message = L.format("update.available", language, ["v": release.version])
            } else {
                available = nil
                message = announceUpToDate ? L.text("update.latest", language) : ""
            }
        } catch {
            // время неудачи тоже помечается, иначе в офлайне программа ходит в сеть при каждом запуске
            lastCheck = Date()
            lastCheckFailed = true
            available = nil
            message = announceUpToDate ? L.describe(error, language) : ""
        }
        isChecking = false
    }

    private func fetched(previous: (etag: String, release: UpdateChecker.ReleaseInfo)?) async throws -> UpdateChecker.ReleaseInfo {
        switch try await UpdateChecker.fetchLatest(etag: previous?.etag) {
        case .release(let release, let etag):
            remember(etag: etag, release: release)
            return release
        case .notModified:
            // 304 приходит только на запрос с etag, а etag хранится вместе с разобранным ответом
            guard let release: UpdateChecker.ReleaseInfo = previous?.release else {
                throw UpdateError.invalidResponse
            }
            return release
        }
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
