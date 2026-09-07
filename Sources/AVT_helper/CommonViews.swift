import SwiftUI

/// подпись секции: заглавными с разрядкой.
/// регистр меняет начертание, а не сам текст: uppercased() отдал бы VoiceOver строку,
/// которую он читает по буквам
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            // мелкий кегль третьей ступенью серого не добирал до контраста 4.5:1,
            // поэтому подпись крупнее на пункт и на ступень темнее
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(.secondary)
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
    let progress: ProgressBox
    /// оба места вызова передают только счётчик, поэтому язык подписи берётся оттуда же,
    /// откуда его берут корневые виды
    @AppStorage(LanguagePreference.storageKey) private var appLanguageRaw: String = LanguagePreference.system.rawValue

    var body: some View {
        let language: AppLanguage = AppLanguage.resolve(appLanguageRaw)
        // процент собирает форматтер: у русского перед знаком неразрывный пробел,
        // и вручную литералом его не получить
        let percent: String = progress.value.formatted(
            .percent.precision(.fractionLength(0)).locale(Locale(identifier: language.rawValue)))
        return HStack(spacing: 10) {
            ProgressView(value: progress.value)
                .frame(width: 120)
            Text(percent)
                .monospacedDigit()
        }
        .font(.footnote)
        // полоса и процент это одно и то же число: порознь VoiceOver читает безымянный индикатор
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.text("progress.label", language))
        .accessibilityValue(percent)
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
            // длинное имя обрезается посередине, и полным его показывает подсказка
            .help(role)
            .accessibilityLabel(role)
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
