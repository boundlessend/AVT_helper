import Foundation

/// состав голосов переживает закрытие листа: у сериала каст один на сезон,
/// и настраивать его заново на каждую серию незачем
@MainActor
final class VoiceSetup: ObservableObject {
    private static let storageKey: String = "voiceSetup"

    /// голосов не может быть больше, чем цветов выделения: девятый голос неотличим от первого
    static let maxVoices: Int = WordHighlightColor.allCases.count

    static let initial: [VoiceConfig] = [
        VoiceConfig(id: 1, gender: .male, color: .yellow),
        VoiceConfig(id: 2, gender: .female, color: .green),
    ]

    @Published var voices: [VoiceConfig] {
        didSet { save() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data: Data = defaults.data(forKey: Self.storageKey),
            let stored: [VoiceConfig] = try? JSONDecoder().decode([VoiceConfig].self, from: data),
            !stored.isEmpty
        else {
            voices = Self.initial
            return
        }
        voices = Array(stored.prefix(Self.maxVoices))
    }

    private func save() {
        guard let data: Data = try? JSONEncoder().encode(voices) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// подгоняет число голосов, выдавая новым ещё не занятый цвет
    func resize(to count: Int) {
        let target: Int = min(max(count, 1), Self.maxVoices)
        if voices.count > target {
            voices = Array(voices.prefix(target))
            return
        }
        while voices.count < target {
            let nextId: Int = (voices.map { voice in voice.id }.max() ?? 0) + 1
            let used: Set<WordHighlightColor> = Set(voices.map { voice in voice.color })
            let free: WordHighlightColor? = WordHighlightColor.allCases.first { color in !used.contains(color) }
            voices.append(
                VoiceConfig(
                    id: nextId,
                    gender: nextId % 2 == 0 ? .female : .male,
                    color: free ?? WordHighlightColor.allCases[(nextId - 1) % WordHighlightColor.allCases.count]
                )
            )
        }
    }
}

enum RoleAssignmentService {
    /// распределяет роли по голосам с учётом пола и текущей нагрузки
    static func assignRoles(
        counts: [String: Int],
        voices: [VoiceConfig],
        roleSettings: [RoleGenderSetting],
        language: AppLanguage
    ) throws -> RoleAssignmentResult {
        if voices.isEmpty {
            throw SubtitleError.exportFailed(L.text("error.noVoices", language))
        }

        // uniquingKeysWith, а не uniqueKeysWithValues: второй падает в trap на повторе ключа,
        // и один дублирующийся список ролей уронил бы программу вместо ошибки
        let genderByRole: [String: VoiceGender] = Dictionary(
            roleSettings.map { setting in (setting.role, setting.gender) },
            uniquingKeysWith: { first, _ in first }
        )
        var loadByVoice: [Int: Int] = Dictionary(
            voices.map { voice in (voice.id, 0) },
            uniquingKeysWith: { first, _ in first }
        )
        var roleToVoice: [String: Int] = [:]

        for gender in VoiceGender.allCases {
            let roles: [(String, Int)] =
                counts
                .filter { role, _ in genderByRole[role] == gender }
                .sorted { left, right in
                    if left.value == right.value {
                        return left.key.localizedCaseInsensitiveCompare(right.key) == .orderedAscending
                    }
                    return left.value > right.value
                }
            if roles.isEmpty {
                continue
            }

            let matchingVoices: [VoiceConfig] = voices.filter { voice in voice.gender == gender }
            if matchingVoices.isEmpty {
                throw SubtitleError.exportFailed(L.format("error.noVoiceForGender", language, ["g": gender.title(language)]))
            }

            for role in roles {
                guard
                    let targetVoice: VoiceConfig = matchingVoices.min(by: { left, right in
                        let leftLoad: Int = loadByVoice[left.id, default: 0]
                        let rightLoad: Int = loadByVoice[right.id, default: 0]
                        if leftLoad == rightLoad {
                            return left.id < right.id
                        }
                        return leftLoad < rightLoad
                    })
                else {
                    throw SubtitleError.exportFailed(L.format("error.cannotPickVoice", language, ["r": role.0]))
                }
                roleToVoice[role.0] = targetVoice.id
                loadByVoice[targetVoice.id, default: 0] += role.1
            }
        }

        let colorByVoice: [Int: WordHighlightColor] = Dictionary(
            voices.map { voice in (voice.id, voice.color) },
            uniquingKeysWith: { first, _ in first }
        )
        let roleToHighlight: [String: WordHighlightColor] = roleToVoice.reduce(
            into: [String: WordHighlightColor]()
        ) { result, item in
            result[item.key] = colorByVoice[item.value]
        }

        return RoleAssignmentResult(roleToVoice: roleToVoice, roleToHighlight: roleToHighlight)
    }
}
