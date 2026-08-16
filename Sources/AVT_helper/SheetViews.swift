import SwiftUI

/// подпись секции монтажного листа: заглавными с разрядкой.
/// регистр меняет начертание, а не сам текст: uppercased() отдал бы VoiceOver строку,
/// которую он читает по буквам
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(.tertiary)
    }
}

/// шапка секции: подпись слева, её кнопки справа. один и тот же ряд стоит над очередью,
/// списком ролей и обеими таблицами разролёвки
struct SectionHeader<Trailing: View>: View {
    let text: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            SectionLabel(text: text)
            Spacer()
            trailing()
        }
    }
}

/// нижний ряд вспомогательного окна: «Закрыть» справа и на Escape, как во всех окнах системы
struct DismissFooter: View {
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Spacer()
            Button(L.text("close", language)) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
    }
}

/// ход работы: полоса и процент рядом. одинаковы в строке состояния и в листе разролёвки
struct ProgressReadout: View {
    @ObservedObject var progress: ProgressBox

    var body: some View {
        HStack(spacing: 10) {
            ProgressView(value: progress.value)
                .frame(width: 120)
            Text("\(Int(progress.value * 100))%")
                .monospacedDigit()
        }
        .font(.footnote)
    }
}

/// имя роли под маркером того цвета, которым роль будет выделена в DOCX
struct RoleTag: View {
    let role: String
    let color: WordHighlightColor?

    var body: some View {
        Text(role)
            .textCase(.uppercase)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.4)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.map { swatch in RoleColors.swatch(swatch) } ?? Color.clear)
            .foregroundStyle(color == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(RoleColors.inkOnSwatch))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .accessibilityLabel(role)
    }
}

/// строка листа: тайминг, роли под маркерами, реплика
struct SheetRow: View {
    let line: SubtitleLine
    let language: AppLanguage
    let highlights: [String: WordHighlightColor]
    let roleWidth: CGFloat

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
            .frame(width: roleWidth, alignment: .leading)

            Text(line.text)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }
}

/// размеры колонок листа: тайминг всегда одной длины, а роль делит остаток с репликой
enum SheetMetrics {
    static let timingWidth: CGFloat = 86

    /// колонка роли растёт вместе с окном, но не съедает реплику и не сжимается до нечитаемой
    static func roleWidth(sheetWidth: CGFloat) -> CGFloat {
        min(280, max(120, sheetWidth * 0.22))
    }
}

/// монтажный лист импортированного файла
struct SubtitleSheetView: View {
    let subtitle: ImportedSubtitle
    let language: AppLanguage
    let highlights: [String: WordHighlightColor]

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 14) {
                    SectionLabel(text: L.text("col.timing", language))
                        .frame(width: SheetMetrics.timingWidth, alignment: .leading)
                    SectionLabel(text: L.text("col.role", language))
                        .frame(width: SheetMetrics.roleWidth(sheetWidth: proxy.size.width), alignment: .leading)
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
                    SheetRow(
                        line: line,
                        language: language,
                        highlights: highlights,
                        roleWidth: SheetMetrics.roleWidth(sheetWidth: proxy.size.width)
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                    .listRowSeparator(.visible)
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 22)
            }
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
                Spacer(minLength: 8)
                if let voice: Int = voice {
                    Text("\(L.text("voiceShort", language))\(voice)")
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

/// кнопка формата экспорта: включённый формат заливается акцентным цветом системы,
/// потому что это выбор пользователя, а не наше представление о выделении
struct FormatToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity)
                .frame(height: 22)
        }
        // без buttonStyle поверх: он перекрывает заливку включённого состояния,
        // и включённый формат становится неотличим от выключенного
        .toggleStyle(.button)
        .tint(.accentColor)
        .accessibilityLabel(title)
    }
}
