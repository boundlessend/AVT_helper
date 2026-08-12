import SwiftUI

/// подпись секции монтажного листа: заглавными с разрядкой
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(.tertiary)
    }
}

/// имя роли под маркером того цвета, которым роль будет выделена в DOCX
struct RoleTag: View {
    let role: String
    let color: WordHighlightColor?

    var body: some View {
        Text(role.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.4)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.map { swatch in RoleColors.swatch(swatch) } ?? Color.clear)
            .foregroundStyle(color == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(RoleColors.inkOnSwatch))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

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
                .frame(width: 86, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(line.displayRoles(language), id: \.self) { role in
                    RoleTag(role: role, color: highlights[role])
                }
            }
            .frame(width: 150, alignment: .leading)

            Text(line.text)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }
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
                    .frame(width: 86, alignment: .leading)
                SectionLabel(text: L.text("col.role", language))
                    .frame(width: 150, alignment: .leading)
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
                Spacer(minLength: 8)
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
        .opacity(isSelected ? 1 : 0.62)
    }
}

/// кнопка формата экспорта: включённый формат заливается основным цветом схемы
struct FormatToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(isOn ? AnyShapeStyle(Color(nsColor: .textBackgroundColor)) : AnyShapeStyle(Color.clear))
                    .frame(width: 5, height: 5)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(isOn ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color(nsColor: .textBackgroundColor)))
            .foregroundStyle(isOn ? AnyShapeStyle(Color(nsColor: .textBackgroundColor)) : AnyShapeStyle(.secondary))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(.quaternary, lineWidth: isOn ? 0 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
