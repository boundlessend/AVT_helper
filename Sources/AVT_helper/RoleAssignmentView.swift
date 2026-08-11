import SwiftUI

struct RoleAssignmentView: View {
    let subtitle: ImportedSubtitle
    let outputFolder: String
    let language: AppLanguage
    let onComplete: (String) -> Void

    /// считается один раз при создании, чтобы не пересчитывать все реплики на каждый рендер списка
    private let roleCounts: [String: Int]

    @Environment(\.dismiss) private var dismiss
    @State private var voices: [VoiceConfig] = [
        VoiceConfig(id: 1, gender: .male, color: .yellow),
        VoiceConfig(id: 2, gender: .female, color: .green),
    ]
    @State private var voiceCount: Int = 2
    @State private var roleSettings: [RoleGenderSetting] = []
    @State private var errorMessage: String = ""
    @State private var isWorking: Bool = false
    @State private var progress: Double = 0

    init(
        subtitle: ImportedSubtitle,
        outputFolder: String,
        language: AppLanguage,
        onComplete: @escaping (String) -> Void
    ) {
        self.subtitle = subtitle
        self.outputFolder = outputFolder
        self.language = language
        self.onComplete = onComplete
        self.roleCounts = RoleAssignmentService.roleReplicaCounts(subtitle: subtitle, language: language)
    }

    /// пол, для ролей которого не назначено ни одного голоса; пока он есть, разролёвка невозможна
    private var genderWithoutVoice: VoiceGender? {
        VoiceGender.allCases.first { gender in
            roleSettings.contains { setting in setting.gender == gender }
                && !voices.contains { voice in voice.gender == gender }
        }
    }

    private var hasDuplicateColors: Bool {
        Set(voices.map { voice in voice.color }).count != voices.count
    }

    private func t(_ key: String) -> String {
        L.text(key, language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WindowHeader(
                title: t("roleAssignment"),
                systemImage: nil,
                closeTitle: t("close"),
                onClose: { dismiss() }
            )

            Stepper("\(t("voiceCount")): \(voiceCount)", value: $voiceCount, in: 1...12)
                .onChange(of: voiceCount) { _, newValue in
                    adjustVoices(count: newValue)
                }

            voiceTable

            Text(t("roles"))
                .font(.headline)
            roleTable

            messages

            HStack(spacing: 10) {
                Spacer()
                if isWorking {
                    ProgressView(value: progress)
                        .frame(width: 130)
                    Text("\(Int(progress * 100))%")
                        .monospacedDigit()
                }
                Button(t("assignRoles")) {
                    assignRoles()
                }
                .keyboardShortcut(.return)
                .disabled(isWorking || genderWithoutVoice != nil)
            }
        }
        .padding(18)
        .onAppear {
            if roleSettings.isEmpty {
                let hints: [String: VoiceGender] = roleGenderHints()
                roleSettings = subtitle.allRoles(language).map { role in
                    RoleGenderSetting(role: role, gender: hints[role] ?? .male)
                }
            }
        }
    }

    /// предупреждения и ошибки показываются здесь же: главное окно закрыто этим листом
    @ViewBuilder
    private var messages: some View {
        if let gender: VoiceGender = genderWithoutVoice {
            Label(
                L.format("error.noVoiceForGender", language, ["g": gender.title(language)]),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.footnote)
            .foregroundStyle(.red)
        } else if hasDuplicateColors {
            Label(t("warning.duplicateColors"), systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
        }

        if !errorMessage.isEmpty {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private func roleGenderHints() -> [String: VoiceGender] {
        subtitle.lines.reduce(into: [String: VoiceGender]()) { result, line in
            guard let gender: VoiceGender = genderHint(sex: line.sex) else {
                return
            }
            for role in line.displayRoles(language) where result[role] == nil {
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
                        genderPicker($voice.gender)
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
                genderPicker($setting.gender)
            }
        }
        .frame(minHeight: 240)
    }

    /// общий выбор пола, используется в таблице голосов и в списке ролей
    private func genderPicker(_ selection: Binding<VoiceGender>) -> some View {
        Picker("", selection: selection) {
            ForEach(VoiceGender.allCases) { gender in
                Text(gender.title(language)).tag(gender)
            }
        }
        .frame(width: 150)
    }

    private func adjustVoices(count: Int) {
        if voices.count > count {
            voices = Array(voices.prefix(count))
            return
        }

        while voices.count < count {
            let nextId: Int = (voices.map { voice in voice.id }.max() ?? 0) + 1
            let used: Set<WordHighlightColor> = Set(voices.map { voice in voice.color })
            let freeColor: WordHighlightColor? = WordHighlightColor.allCases.first { color in !used.contains(color) }
            let fallback: WordHighlightColor = WordHighlightColor.allCases[(nextId - 1) % WordHighlightColor.allCases.count]
            voices.append(
                VoiceConfig(
                    id: nextId,
                    gender: nextId % 2 == 0 ? .female : .male,
                    color: freeColor ?? fallback
                )
            )
        }
    }

    private func assignRoles() {
        isWorking = true
        progress = 0
        errorMessage = ""
        Task {
            do {
                let result: RoleAssignmentResult = try RoleAssignmentService.assignRoles(
                    subtitle: subtitle,
                    voices: voices,
                    roleSettings: roleSettings,
                    language: language
                )
                let voiceSummaries: [VoiceRoleSummary] = buildVoiceSummaries(result: result)
                let exportSubtitle: ImportedSubtitle = subtitle
                let exportFolder: String = outputFolder
                let exportLanguage: AppLanguage = language
                let suffix: String = L.text("file.assignmentSuffix", language)
                let path: String = try await Task.detached(priority: .userInitiated) {
                    var paths: OutputPathAllocator = OutputPathAllocator(sourcePath: exportSubtitle.sourcePath)
                    return try DocxExporter.export(
                        subtitle: exportSubtitle,
                        outputFolder: exportFolder,
                        language: exportLanguage,
                        paths: &paths,
                        roleHighlights: result.roleToHighlight,
                        voiceSummaries: voiceSummaries,
                        fileSuffix: suffix,
                        progress: { fraction in
                            Task { @MainActor in
                                progress = fraction
                            }
                        }
                    )
                }.value
                isWorking = false
                onComplete(path)
                dismiss()
            } catch {
                isWorking = false
                errorMessage = L.describe(error, language)
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
