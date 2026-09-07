import SwiftUI

/// левый рельс: всё, что задаёт выгрузку, собрано в одном столбце и не спорит с листом за внимание
struct ExportRailView: View {
    let model: ProcessingModel
    @Bindable var options: ExportOptions
    let language: AppLanguage
    let onChooseInput: () -> Void
    let onChooseOutputFolder: () -> Void

    /// путь редактируется в поле, а в настройки уезжает по концу ввода: иначе каждый символ
    /// пересобирал бы всё окно вместе с монтажным листом и писал бы в UserDefaults
    @State private var outputFolderText: String = ""
    /// проверка папки ходит в файловую систему, поэтому её результат хранится,
    /// а не считается заново на каждой перерисовке
    @State private var isOutputFolderUsable: Bool = true
    @FocusState private var isOutputFolderFocused: Bool

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
                // список, а не столбец кнопок: выделение, стрелки и Delete нужны с клавиатуры,
                // и всё это список умеет сам
                List(selection: queueSelection) {
                    ForEach(model.queue) { file in
                        QueueRow(file: file, language: language, onRemove: { remove(file) })
                            .tag(file.id)
                            .listRowInsets(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4))
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 25)
                .frame(height: queueHeight)
                .onDeleteCommand(perform: removeSelected)
                Button(t("queue.add"), action: onChooseInput)
                    .controlSize(.small)
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: t("outputFolder"))
            HStack(spacing: 6) {
                TextField(t("outputFolder"), text: $outputFolderText)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .font(.system(size: 11, design: .monospaced))
                    .accessibilityLabel(t("outputFolder"))
                    .focused($isOutputFolderFocused)
                    .onSubmit(commitOutputFolder)
                    .onChange(of: isOutputFolderFocused) { _, isFocused in
                        if !isFocused {
                            commitOutputFolder()
                        }
                    }
                Button(action: onChooseOutputFolder) {
                    Image(systemName: "folder")
                }
                .help(t("chooseOutputFolder"))
                .accessibilityLabel(t("chooseOutputFolder"))
            }
            if !isOutputFolderUsable {
                Label(t("hint.badOutputFolder"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            showOutputFolder(options.outputFolder)
        }
        .onChange(of: options.outputFolder) { _, path in
            showOutputFolder(path)
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

    /// выделение списка это тот же выбранный файл: список показывает его и через него же меняет
    private var queueSelection: Binding<QueuedFile.ID?> {
        Binding(
            get: { model.selectedFileID },
            set: { id in
                guard let id: QueuedFile.ID = id, id != model.selectedFileID else {
                    return
                }
                Task { await model.select(id, language: language) }
            }
        )
    }

    /// очередь растёт вместе со списком, но выше этого предела забирала бы весь рельс себе
    private var queueHeight: CGFloat {
        min(216, CGFloat(model.queue.count) * 27 + 4)
    }

    private func showOutputFolder(_ path: String) {
        outputFolderText = path
        isOutputFolderUsable = OutputFolder.isUsable(path)
    }

    private func commitOutputFolder() {
        isOutputFolderUsable = OutputFolder.isUsable(outputFolderText)
        guard outputFolderText != options.outputFolder else {
            return
        }
        options.outputFolder = outputFolderText
    }

    private func remove(_ file: QueuedFile) {
        Task { await model.remove(file.id, language: language) }
    }

    private func removeSelected() {
        guard let id: QueuedFile.ID = model.selectedFileID else {
            return
        }
        Task { await model.remove(id, language: language) }
    }
}

/// строка очереди: имя файла, исход прошлого прогона и кнопка убрать.
/// выделение рисует сам список, поэтому строка о нём не знает
struct QueueRow: View {
    let file: QueuedFile
    let language: AppLanguage
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                stateIcon
                Text(file.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // цвет значка исход прогона не передаёт: имя и состояние читаются одной подписью,
            // а причина отказа или число файлов идут значением
            .accessibilityElement(children: .combine)
            .accessibilityValue(stateDetail)
            .help(stateDetail)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help(L.text("queue.remove", language))
            .accessibilityLabel(L.text("queue.remove", language))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch file.state {
        case .waiting:
            Image(systemName: "doc.text")
                .foregroundStyle(.tertiary)
                .accessibilityLabel(L.text("queue.state.waiting", language))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel(L.text("queue.state.done", language))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel(L.text("queue.state.failed", language))
        }
    }

    private var stateDetail: String {
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
