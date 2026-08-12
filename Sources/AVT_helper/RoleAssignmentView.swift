import SwiftUI

struct RoleAssignmentView: View {
    let subtitle: ImportedSubtitle
    /// роли и счётчики, уже посчитанные при импорте
    let digest: SubtitleDigest
    let outputFolder: String
    let language: AppLanguage
    let onComplete: (String, RoleAssignmentResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var voices: [VoiceConfig] = [
        VoiceConfig(id: 1, gender: .male, color: .yellow),
        VoiceConfig(id: 2, gender: .female, color: .green),
    ]
    @State private var voiceCount: Int = 2
    @State private var roleSettings: [RoleGenderSetting] = []
    /// распределение при текущих настройках; пересчитывается по действию, а не в body
    @State private var preview: RoleAssignmentResult?
    /// причина, по которой распределение невозможно: она же не даёт запустить разролёвку
    @State private var previewError: String = ""
    @State private var errorMessage: String = ""
    @State private var isWorking: Bool = false
    @State private var progress: Double = 0

    private var hasDuplicateColors: Bool {
        Set(voices.map { voice in voice.color }).count != voices.count
    }

    private var previewHighlights: [String: WordHighlightColor] {
        preview?.roleToHighlight ?? [:]
    }

    private func t(_ key: String) -> String {
        L.text(key, language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            voicePanel
            rolePanel
            messages
            footer
        }
        .padding(18)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if roleSettings.isEmpty {
                let hints: [String: VoiceGender] = roleGenderHints()
                roleSettings = digest.roles.map { role in
                    RoleGenderSetting(role: role, gender: hints[role] ?? .male)
                }
            }
            refreshPreview()
        }
        .onChange(of: voices.map { voice in voice.color }) { _, _ in
            refreshPreview()
        }
        .onChange(of: voices.map { voice in voice.gender }) { _, _ in
            refreshPreview()
        }
        .onChange(of: roleSettings.map { setting in setting.gender }) { _, _ in
            refreshPreview()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(t("roleAssignment"))
                    .font(.system(size: 21, weight: .bold))
                Text(subtitle.baseName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(t("close")) {
                dismiss()
            }
        }
    }

    private var voicePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: t("voices"))
                Spacer()
                Stepper("\(t("voiceCount")): \(voiceCount)", value: $voiceCount, in: 1...12)
                    .font(.system(size: 12))
                    .fixedSize()
                    .onChange(of: voiceCount) { _, newValue in
                        adjustVoices(count: newValue)
                    }
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    SectionLabel(text: t("voice"))
                    SectionLabel(text: t("highlightColor"))
                    SectionLabel(text: t("gender"))
                    SectionLabel(text: t("roles"))
                }
                ForEach($voices) { $voice in
                    GridRow {
                        Text("\(t("voice")) \(voice.id)")
                            .font(.system(size: 12.5, weight: .medium))
                        Picker("", selection: $voice.color) {
                            ForEach(WordHighlightColor.allCases) { color in
                                HStack {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(RoleColors.swatch(color))
                                        .frame(width: 18, height: 18)
                                    Text(color.title(language))
                                }
                                .tag(color)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                        genderPicker($voice.gender)
                        Text(rolesOfVoice(voice.id))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    private var rolePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "\(t("roles")) · \(roleSettings.count)")
            List($roleSettings) { $setting in
                HStack(spacing: 10) {
                    RoleTag(role: setting.role, color: previewHighlights[setting.role])
                        .frame(width: 190, alignment: .leading)
                    Text("\(digest.counts[setting.role, default: 0]) \(t("lineCountSuffix"))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                    Spacer(minLength: 12)
                    genderPicker($setting.gender)
                }
                .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
            }
            .listStyle(.plain)
            .frame(minHeight: 240)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 1)
            }
        }
    }

    /// предупреждения и ошибки показываются здесь же: главное окно закрыто этим листом
    @ViewBuilder
    private var messages: some View {
        if !previewError.isEmpty {
            Label(previewError, systemImage: "exclamationmark.triangle.fill")
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

    private var footer: some View {
        HStack(spacing: 10) {
            Text(t("roles.previewHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if isWorking {
                ProgressView(value: progress)
                    .frame(width: 120)
                Text("\(Int(progress * 100))%")
                    .monospacedDigit()
                    .font(.footnote)
            }
            Button(t("assignRoles")) {
                assignRoles()
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || preview == nil)
        }
    }

    /// роли, которые достанутся голосу при текущих настройках: строка в таблице голосов
    private func rolesOfVoice(_ voiceId: Int) -> String {
        let names: [String] = (preview?.roleToVoice ?? [:])
            .filter { _, assigned in assigned == voiceId }
            .keys
            .sorted { left, right in left.localizedCaseInsensitiveCompare(right) == .orderedAscending }
        return names.joined(separator: ", ")
    }

    /// пересчитывает предполагаемое распределение и держит причину отказа на виду
    private func refreshPreview() {
        do {
            preview = try RoleAssignmentService.assignRoles(
                counts: digest.counts,
                voices: voices,
                roleSettings: roleSettings,
                language: language
            )
            previewError = ""
        } catch {
            preview = nil
            previewError = L.describe(error, language)
        }
    }

    private func roleGenderHints() -> [String: VoiceGender] {
        subtitle.lines.reduce(into: [String: VoiceGender]()) { result, line in
            guard let gender: VoiceGender = line.sex.voiceGender else {
                return
            }
            for role in line.displayRoles(language) where result[role] == nil {
                result[role] = gender
            }
        }
    }

    /// общий выбор пола, используется в таблице голосов и в списке ролей
    private func genderPicker(_ selection: Binding<VoiceGender>) -> some View {
        Picker("", selection: selection) {
            ForEach(VoiceGender.allCases) { gender in
                Text(gender.title(language)).tag(gender)
            }
        }
        .labelsHidden()
        .frame(width: 140)
    }

    private func adjustVoices(count: Int) {
        if voices.count > count {
            voices = Array(voices.prefix(count))
            refreshPreview()
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
        refreshPreview()
    }

    private func assignRoles() {
        // папку могли удалить или переименовать, пока окно открыто: без неё запись даст системную ошибку
        guard OutputFolder.isUsable(outputFolder) else {
            errorMessage = t("hint.badOutputFolder")
            return
        }
        isWorking = true
        progress = 0
        errorMessage = ""
        Task {
            do {
                let result: RoleAssignmentResult = try RoleAssignmentService.assignRoles(
                    counts: digest.counts,
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
                                // порядок доставки задач не гарантирован, поэтому полоска только растёт
                                if fraction > progress {
                                    progress = fraction
                                }
                            }
                        }
                    )
                }.value
                isWorking = false
                onComplete(path, result)
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
