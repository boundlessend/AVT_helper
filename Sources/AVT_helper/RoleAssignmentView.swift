import SwiftUI

struct RoleAssignmentView: View {
    let model: ProcessingModel
    let subtitle: ImportedSubtitle
    /// роли и счётчики, уже посчитанные при импорте
    let digest: SubtitleDigest
    let outputFolder: String
    let language: AppLanguage
    let onComplete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var setup: VoiceSetup = VoiceSetup()
    @State private var roleSettings: [RoleGenderSetting] = []
    /// распределение при текущих настройках; пересчитывается по действию, а не в body
    @State private var preview: RoleAssignmentResult?
    /// причина, по которой распределение невозможно: она же не даёт запустить разролёвку
    @State private var previewError: String = ""
    @State private var errorMessage: String = ""
    /// отмену просил сам пользователь: показывать её ошибкой незачем, а модель о просьбе не помнит
    @State private var didCancel: Bool = false

    private var hasDuplicateColors: Bool {
        Set(setup.voices.map { voice in voice.color }).count != setup.voices.count
    }

    /// роли без подставленной метки «нет роли»: голос и цвет ей не полагаются,
    /// ровно как и в автоматической раскраске
    private var namedRoles: [String] {
        digest.roles.filter { role in role != digest.placeholder }
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
                // пол ролей приносит только SRP: без подсказок весь каст пришёл бы мужским,
                // поэтому он чередуется по порядку ролей, а кнопки «все мужские» и «все женские» это переопределяют
                let hints: [String: VoiceGender] = roleGenderHints()
                roleSettings = namedRoles.enumerated().map { index, role in
                    let byOrder: VoiceGender = index.isMultiple(of: 2) ? .male : .female
                    return RoleGenderSetting(role: role, gender: hints[role] ?? (hints.isEmpty ? byOrder : .male))
                }
            }
            refreshPreview()
        }
        .onChange(of: setup.voices.map { voice in voice.color }) { _, _ in
            refreshPreview()
        }
        .onChange(of: setup.voices.map { voice in voice.gender }) { _, _ in
            refreshPreview()
        }
        .onChange(of: roleSettings.map { setting in setting.gender }) { _, _ in
            refreshPreview()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t("roleAssignment"))
                .font(.system(size: 21, weight: .bold))
            Text(subtitle.baseName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var voicePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(text: t("voices")) {
                Stepper(
                    "\(t("voiceCount")): \(setup.voices.count)",
                    value: Binding(
                        get: { setup.voices.count },
                        set: { count in setup.resize(to: count) }
                    ),
                    in: 1...VoiceSetup.maxVoices
                )
                .font(.system(size: 12))
                .fixedSize()
                .onChange(of: setup.voices.count) { _, _ in
                    refreshPreview()
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    SectionLabel(text: t("voice"))
                    SectionLabel(text: t("highlightColor"))
                    SectionLabel(text: t("gender"))
                    SectionLabel(text: t("roles"))
                }
                ForEach($setup.voices) { $voice in
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
                        .accessibilityLabel("\(t("voice")) \(voice.id), \(t("highlightColor"))")
                        genderPicker($voice.gender, label: "\(t("voice")) \(voice.id), \(t("gender"))")
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
            SectionHeader(text: L.plural("count.roles", language, roleSettings.count)) {
                // двадцать ролей поштучно через выпадающий список никто не переберёт,
                // а исходник пол приносит только у SRP
                Text(t("gender.setAll"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button(VoiceGender.male.title(language)) {
                    setAllGenders(.male)
                }
                Button(VoiceGender.female.title(language)) {
                    setAllGenders(.female)
                }
            }
            .controlSize(.small)

            List($roleSettings) { $setting in
                HStack(spacing: 10) {
                    RoleTag(role: setting.role, color: previewHighlights[setting.role])
                        .frame(width: 190, alignment: .leading)
                    Text(L.plural("count.lines", language, digest.counts[setting.role, default: 0]))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .trailing)
                    Spacer(minLength: 12)
                    genderPicker($setting.gender, label: "\(setting.role), \(t("gender"))")
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

    /// кнопки внизу справа, отмена слева от основной и на Escape: так закрываются
    /// все системные листы, и рука ищет их именно там
    private var footer: some View {
        HStack(spacing: 10) {
            Text(t("roles.previewHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if model.isWorking {
                ProgressReadout(progress: model.progress)
            }
            // одна и та же кнопка: пока идёт запись, «Отменить» отменяет её, а не закрывает лист
            Button(t("cancel")) {
                if model.isWorking {
                    didCancel = true
                    model.cancel()
                } else {
                    dismiss()
                }
            }
            .keyboardShortcut(.cancelAction)
            Button(t("assignRoles")) {
                assignRoles()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.isWorking || preview == nil)
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
                counts: digest.namedCounts,
                voices: setup.voices,
                roleSettings: roleSettings,
                language: language
            )
            previewError = ""
        } catch {
            preview = nil
            previewError = L.describe(error, language)
        }
    }

    private func setAllGenders(_ gender: VoiceGender) {
        for index in roleSettings.indices {
            roleSettings[index].gender = gender
        }
        refreshPreview()
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
    private func genderPicker(_ selection: Binding<VoiceGender>, label: String) -> some View {
        Picker("", selection: selection) {
            ForEach(VoiceGender.allCases) { gender in
                Text(gender.title(language)).tag(gender)
            }
        }
        .labelsHidden()
        .frame(width: 140)
        .accessibilityLabel(label)
    }

    private func assignRoles() {
        // папку могли удалить или переименовать, пока окно открыто: без неё запись даст системную ошибку
        guard OutputFolder.isUsable(outputFolder) else {
            errorMessage = t("hint.badOutputFolder")
            return
        }
        errorMessage = ""
        didCancel = false
        Task {
            let created: String? = await model.makeRoleAssignment(
                subtitle: subtitle,
                digest: digest,
                voices: setup.voices,
                roleSettings: roleSettings,
                outputFolder: outputFolder,
                language: language
            )
            guard let path: String = created else {
                // причину модель записала в журнал; главное окно закрыто листом, поэтому она нужна здесь
                if !didCancel {
                    errorMessage = model.status
                }
                return
            }
            onComplete(path)
            dismiss()
        }
    }
}
