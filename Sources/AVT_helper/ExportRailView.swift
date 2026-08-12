import SwiftUI

/// левый рельс: всё, что задаёт выгрузку, собрано в одном столбце и не спорит с листом за внимание
struct ExportRailView: View {
    @ObservedObject var options: ExportOptions
    let language: AppLanguage
    let subtitle: ImportedSubtitle?
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
        .frame(width: 238)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: t("source"))
            Button(action: onChooseInput) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subtitle.map { file in file.baseName } ?? t("notSelected"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(subtitle == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    if let file: ImportedSubtitle = subtitle {
                        Text("\(file.sourceType.rawValue) · \(file.lines.count) \(t("lines"))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
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
}
