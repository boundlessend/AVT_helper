import SwiftUI

struct RoleAssignmentView: View {
    let subtitle: ImportedSubtitle
    let outputFolder: String
    let language: AppLanguage
    let onComplete: (String) -> Void
    let onError: (String) -> Void

    /// считается один раз при создании, чтобы не пересчитывать все реплики на каждый рендер списка
    private let roleCounts: [String: Int]

    @Environment(\.dismiss) private var dismiss
    @State private var voices: [VoiceConfig] = [
        VoiceConfig(id: 1, gender: .male, color: .yellow),
        VoiceConfig(id: 2, gender: .female, color: .green),
    ]
    @State private var voiceCount: Int = 2
    @State private var roleSettings: [RoleGenderSetting] = []
    @State private var assignmentSummary: String = ""
    @State private var isWorking: Bool = false

    init(
        subtitle: ImportedSubtitle,
        outputFolder: String,
        language: AppLanguage,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.subtitle = subtitle
        self.outputFolder = outputFolder
        self.language = language
        self.onComplete = onComplete
        self.onError = onError
        self.roleCounts = RoleAssignmentService.roleReplicaCounts(subtitle: subtitle)
    }

    private func t(_ key: String) -> String {
        L.text(key, language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(t("roleAssignment"))
                    .font(.title2.weight(.bold))
                Spacer()
                Button(t("close")) {
                    dismiss()
                }
            }

            Stepper("\(t("voiceCount")): \(voiceCount)", value: $voiceCount, in: 1...12)
                .onChange(of: voiceCount) { _, newValue in
                    adjustVoices(count: newValue)
                }

            voiceTable

            Text(t("roles"))
                .font(.headline)
            roleTable

            if !assignmentSummary.isEmpty {
                Text(assignmentSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(t("assignRoles")) {
                    assignRoles()
                }
                .keyboardShortcut(.return)
                .disabled(isWorking)
            }
        }
        .padding(18)
        .onAppear {
            if roleSettings.isEmpty {
                let hints: [String: VoiceGender] = roleGenderHints()
                roleSettings = subtitle.allRoles.map { role in
                    RoleGenderSetting(role: role, gender: hints[role] ?? .male)
                }
            }
        }
    }

    private func roleGenderHints() -> [String: VoiceGender] {
        subtitle.lines.reduce(into: [String: VoiceGender]()) { result, line in
            guard let gender: VoiceGender = genderHint(sex: line.sex) else {
                return
            }
            for role in line.effectiveRoles where result[role] == nil {
                result[role] = gender
            }
        }
    }

    private func genderHint(sex: String) -> VoiceGender? {
        switch sex {
        case "МУЖ":
            return .male
        case "ЖЕН":
            return .female
        default:
            return nil
        }
    }

    private var voiceTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("voices"))
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text(t("voice")).fontWeight(.semibold)
                    Text(t("highlightColor")).fontWeight(.semibold)
                    Text(t("gender")).fontWeight(.semibold)
                }
                ForEach($voices) { $voice in
                    GridRow {
                        Text("\(t("voice")) \(voice.id)")
                        Picker("", selection: $voice.color) {
                            ForEach(WordHighlightColor.allCases) { color in
                                HStack {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(color.previewColor)
                                        .frame(width: 18, height: 18)
                                    Text(color.title(language))
                                }
                                .tag(color)
                            }
                        }
                        .frame(width: 210)
                        Picker("", selection: $voice.gender) {
                            ForEach(VoiceGender.allCases) { gender in
                                Text(gender.title(language)).tag(gender)
                            }
                        }
                        .frame(width: 150)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var roleTable: some View {
        List($roleSettings) { $setting in
            HStack {
                Text(setting.role)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(roleCounts[setting.role, default: 0]) \(t("lineCountSuffix"))")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                Picker("", selection: $setting.gender) {
                    ForEach(VoiceGender.allCases) { gender in
                        Text(gender.title(language)).tag(gender)
                    }
                }
                .frame(width: 150)
            }
        }
        .frame(minHeight: 240)
    }

    private func adjustVoices(count: Int) {
        if voices.count > count {
            voices = Array(voices.prefix(count))
            return
        }

        while voices.count < count {
            let nextId: Int = (voices.map { voice in voice.id }.max() ?? 0) + 1
            let gender: VoiceGender = nextId % 2 == 0 ? .female : .male
            let color: WordHighlightColor = WordHighlightColor.allCases[(nextId - 1) % WordHighlightColor.allCases.count]
            voices.append(VoiceConfig(id: nextId, gender: gender, color: color))
        }
    }

    private func assignRoles() {
        isWorking = true
        Task {
            do {
                let result: RoleAssignmentResult = try RoleAssignmentService.assignRoles(
                    subtitle: subtitle,
                    voices: voices,
                    roleSettings: roleSettings
                )
                let voiceSummaries: [VoiceRoleSummary] = buildVoiceSummaries(result: result)
                let exportSubtitle: ImportedSubtitle = subtitle
                let exportFolder: String = outputFolder
                let suffix: String = L.text("file.assignmentSuffix", language)
                let path: String = try await Task.detached(priority: .userInitiated) {
                    try DocxExporter.export(
                        subtitle: exportSubtitle,
                        outputFolder: exportFolder,
                        roleHighlights: result.roleToHighlight,
                        voiceSummaries: voiceSummaries,
                        fileSuffix: suffix
                    )
                }.value
                assignmentSummary = buildSummary(result: result)
                isWorking = false
                onComplete(path)
                dismiss()
            } catch {
                isWorking = false
                onError(error.localizedDescription)
            }
        }
    }

    private func buildVoiceSummaries(result: RoleAssignmentResult) -> [VoiceRoleSummary] {
        voices.compactMap { voice in
            let roles: [String] = result.roleToVoice
                .filter { item in item.value == voice.id }
                .map { item in item.key }
                .sorted { left, right in
                    left.localizedCaseInsensitiveCompare(right) == .orderedAscending
                }
            if roles.isEmpty {
                return nil
            }
            return VoiceRoleSummary(voice: voice, roles: roles)
        }
    }

    private func buildSummary(result: RoleAssignmentResult) -> String {
        let counts: [String: Int] = roleCounts
        let loadByVoice: [Int: Int] = result.roleToVoice.reduce(into: [Int: Int]()) { result, item in
            result[item.value, default: 0] += counts[item.key, default: 0]
        }
        return voices.map { voice in
            "\(t("voice")) \(voice.id): \(loadByVoice[voice.id, default: 0]) \(t("lineCountSuffix"))"
        }.joined(separator: "  ")
    }
}

private extension WordHighlightColor {
    var previewColor: Color {
        switch self {
        case .yellow:
            return .yellow
        case .green:
            return .green
        case .cyan:
            return .cyan
        case .magenta:
            return .pink
        case .blue:
            return .blue
        case .red:
            return .red
        case .darkYellow:
            return Color(red: 0.72, green: 0.58, blue: 0.05)
        case .lightGray:
            return .gray
        }
    }
}
