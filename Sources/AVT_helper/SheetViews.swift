import SwiftUI

/// строка листа: тайминг, роли под маркерами, реплика
struct SheetRow: View {
    let line: SubtitleLine
    let language: AppLanguage
    let highlights: [String: WordHighlightColor]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(TimeTools.formatSrt(line.start))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: SheetMetrics.timingWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(line.displayRoles(language), id: \.self) { role in
                    RoleTag(role: role, color: highlights[role])
                }
            }
            .frame(width: SheetMetrics.roleWidth, alignment: .leading)

            Text(line.text)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }
}

/// размеры колонок листа: обе постоянны, остаток ширины забирает реплика.
/// от ширины окна колонки не зависят намеренно: иначе перетаскивание разделителя
/// пересобирало бы каждую строку листа
enum SheetMetrics {
    static let timingWidth: CGFloat = 86
    /// колонка роли: длинное имя показывает подсказка, а не растянутая на весь лист колонка
    static let roleWidth: CGFloat = 130
}

/// монтажный лист импортированного файла
struct SubtitleSheetView: View {
    let subtitle: ImportedSubtitle
    let language: AppLanguage
    let highlights: [String: WordHighlightColor]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 14) {
                SectionLabel(text: L.text("col.timing", language))
                    .frame(width: SheetMetrics.timingWidth, alignment: .leading)
                SectionLabel(text: L.text("col.role", language))
                    .frame(width: SheetMetrics.roleWidth, alignment: .leading)
                SectionLabel(text: L.text("col.replica", language))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.65))
                    .frame(height: 1)
            }

            List(subtitle.lines) { line in
                SheetRow(line: line, language: language, highlights: highlights)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                    .listRowSeparator(.visible)
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 22)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// пустой лист: перетаскивание работает на всей области, поэтому подсказка живёт по центру
struct SheetEmptyView: View {
    let language: AppLanguage
    let isDropTargeted: Bool
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L.text("dropHint", language))
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.center)
            Text("ASS, SSA, SRT, VTT, SRP")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(L.text("openSubtitles", language), action: onOpen)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(isDropTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .textBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [7, 5]))
                .foregroundStyle(isDropTargeted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                .padding(18)
        }
    }
}

/// строка списка ролей: отметка, цвет маркера, число реплик и доля от всего файла
struct RoleRow: View {
    let role: String
    let count: Int
    let share: Double
    let color: WordHighlightColor?
    /// номер назначенного голоса; до разролёвки его нет
    let voice: Int?
    /// отметка что-то значит только при раздельных файлах по ролям
    let isSelectable: Bool
    let language: AppLanguage
    @Binding var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Toggle(isOn: $isSelected) {
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color.map { swatch in RoleColors.swatch(swatch) } ?? Color.clear)
                            .frame(width: 10, height: 10)
                            .overlay {
                                if color == nil {
                                    RoundedRectangle(cornerRadius: 2).strokeBorder(.quaternary, lineWidth: 1)
                                }
                            }
                        Text(role)
                            .font(.system(size: 12.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!isSelectable)
                // длинное имя обрезается посередине, и полным его показывает подсказка
                .help(role)
                Spacer(minLength: 8)
                if let voice: Int = voice {
                    Text(L.format("voiceShort", language, ["n": String(voice)]))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .overlay {
                            RoundedRectangle(cornerRadius: 3).strokeBorder(.quaternary, lineWidth: 1)
                        }
                }
                Text("\(count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(color.map { swatch in RoleColors.swatch(swatch) } ?? Color.secondary.opacity(0.4))
                        .frame(width: max(2, proxy.size.width * share))
                }
            }
            .frame(height: 3)
            .padding(.leading, 20)
        }
        .padding(.vertical, 2)
        .opacity(isSelectable && !isSelected ? 0.62 : 1)
    }
}
