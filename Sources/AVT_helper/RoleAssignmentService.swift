import Foundation

enum RoleAssignmentService {
    static func roleReplicaCounts(subtitle: ImportedSubtitle, language: AppLanguage) -> [String: Int] {
        subtitle.lines.reduce(into: [String: Int]()) { result, line in
            for role in line.displayRoles(language) {
                result[role, default: 0] += 1
            }
        }
    }

    /// распределяет роли по голосам с учётом пола и текущей нагрузки
    static func assignRoles(
        subtitle: ImportedSubtitle,
        voices: [VoiceConfig],
        roleSettings: [RoleGenderSetting],
        language: AppLanguage
    ) throws -> RoleAssignmentResult {
        if voices.isEmpty {
            throw SubtitleError.exportFailed(L.text("error.noVoices", language))
        }

        let counts: [String: Int] = roleReplicaCounts(subtitle: subtitle, language: language)
        let genderByRole: [String: VoiceGender] = Dictionary(
            uniqueKeysWithValues: roleSettings.map { setting in
                (setting.role, setting.gender)
            })
        var loadByVoice: [Int: Int] = Dictionary(
            uniqueKeysWithValues: voices.map { voice in
                (voice.id, 0)
            })
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
            uniqueKeysWithValues: voices.map { voice in
                (voice.id, voice.color)
            })
        let roleToHighlight: [String: WordHighlightColor] = Dictionary(
            uniqueKeysWithValues: roleToVoice.compactMap { role, voiceId in
                guard let color: WordHighlightColor = colorByVoice[voiceId] else {
                    return nil
                }
                return (role, color)
            })

        return RoleAssignmentResult(roleToVoice: roleToVoice, roleToHighlight: roleToHighlight)
    }
}
