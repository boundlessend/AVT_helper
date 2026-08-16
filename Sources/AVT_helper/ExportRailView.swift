import SwiftUI

/// левый рельс: всё, что задаёт выгрузку, собрано в одном столбце и не спорит с листом за внимание
struct ExportRailView: View {
    @ObservedObject var model: ProcessingModel
    @ObservedObject var options: ExportOptions
    let language: AppLanguage
    let onChooseInput: () -> Void
    let onChooseOutputFolder: () -> Void

    private func t(_ key: String) -> String {
        L.text(key, language)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                sourceSection
                outputSection
                formatsSection
                srtSection
                afterSection
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// очередь файлов: сезон ставят целиком и прогоняют одними настройками,
    /// а показанный файл выбирают здесь же
    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(text: t("source")) {
                if !model.queue.isEmpty {
                    Button(t("queue.clear")) {
                        model.clearQueue()
                    }
                    .controlSize(.small)
                    .buttonStyle(.link)
                }
            }

            if model.queue.isEmpty {
                Button(action: onChooseInput) {
                    Text(t("notSelected"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .help(t("openSubtitles"))
            } else {
                VStack(spacing: 4) {
                    ForEach(model.queue) { file in
                        QueueRow(
                            file: file,
                            isSelected: file.id == model.selectedFileID,
                            language: language,
                            onSelect: { select(file) },
                            onRemove: { remove(file) }
                        )
                    }
                }
                Button(t("queue.add"), action: onChooseInput)
                    .controlSize(.small)
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: t("outputFolder"))
            HStack(spacing: 6) {
                TextField(t("outputFolder"), text: $options.outputFolder)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .font(.system(size: 11, design: .monospaced))
                    .accessibilityLabel(t("outputFolder"))
                Button(action: onChooseOutputFolder) {
                    Image(systemName: "folder")
                }
                .help(t("chooseOutputFolder"))
            }
            if !OutputFolder.isUsable(options.outputFolder) {
                Label(t("hint.badOutputFolder"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var formatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: t("export"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                FormatToggle(title: "SRT", isOn: $options.srt)
                FormatToggle(title: "DOCX", isOn: $options.docx)
                FormatToggle(title: "ASS", isOn: $options.ass)
                FormatToggle(title: "VTT", isOn: $options.vtt)
            }
        }
    }

    private var srtSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: t("srtSettings"))
            VStack(alignment: .leading, spacing: 7) {
                Toggle(t("fullWithRoles"), isOn: $options.srtFullWithRoles)
                Toggle(t("separateByRole"), isOn: $options.srtSeparateFiles)
                // префикс роли - свойство тех же файлов, а не отдельный набор: вложен и гаснет без них
                Toggle(t("separateWithPrefix"), isOn: $options.srtSeparateWithRoles)
                    .padding(.leading, 18)
                    .disabled(!options.srtSeparateFiles)
            }
            .font(.system(size: 12))
            .disabled(!options.srt)
        }
    }

    private var afterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: t("afterProcessing"))
            VStack(alignment: .leading, spacing: 7) {
                Toggle(t("openFolderAfter"), isOn: $options.openFolderAfter)
                Toggle(t("closeAppAfter"), isOn: $options.closeAppAfter)
            }
            .font(.system(size: 12))
        }
    }

    private func select(_ file: QueuedFile) {
        Task { await model.select(file.id, language: language) }
    }

    private func remove(_ file: QueuedFile) {
        Task { await model.remove(file.id, language: language) }
    }
}

/// строка очереди: имя файла, исход прошлого прогона и кнопка убрать
struct QueueRow: View {
    let file: QueuedFile
    let isSelected: Bool
    let language: AppLanguage
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    stateIcon
                    Text(file.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.16)) : AnyShapeStyle(Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help(stateHelp)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help(L.text("queue.remove", language))
            .accessibilityLabel(L.text("queue.remove", language))
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch file.state {
        case .waiting:
            Image(systemName: "doc.text")
                .foregroundStyle(.tertiary)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var stateHelp: String {
        switch file.state {
        case .waiting:
            return file.path
        case .done(let count):
            return L.plural("count.files", language, count)
        case .failed(let message):
            return message
        }
    }
}
