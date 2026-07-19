import Foundation

enum L {
    static func text(_ key: String, _ language: AppLanguage) -> String {
        values[key]?[language] ?? values[key]?[.ru] ?? key
    }

    /// подставляет значения в плейсхолдеры вида {token} локализованной строки
    static func format(_ key: String, _ language: AppLanguage, _ replacements: [String: String]) -> String {
        replacements.reduce(text(key, language)) { partial, pair in
            partial.replacingOccurrences(of: "{\(pair.key)}", with: pair.value)
        }
    }

    private static let values: [String: [AppLanguage: String]] = [
        "about": [.ru: "О программе", .en: "About"],
        "about.description": [
            .ru: "Конвертирует ASS, SSA, SRT, VTT и SRP в популярные форматы субтитров и DOCX с ролями, таймингами, репликами и статистикой.",
            .en: "Converts ASS, SSA, SRT, VTT, and SRP into popular subtitle formats and DOCX files with roles, timings, dialogue, and statistics.",
        ],
        "version": [.ru: "Версия", .en: "Version"],
        "qa": [.ru: "Q&A", .en: "Q&A"],
        "settings": [.ru: "Настройки", .en: "Settings"],
        "openSubtitles": [.ru: "Открыть субтитры", .en: "Open subtitles"],
        "chooseOutputFolder": [.ru: "Выбрать папку выгрузки", .en: "Choose output folder"],
        "start": [.ru: "Начать", .en: "Start"],
        "makeRoleAssignment": [.ru: "Сделать разролёвку", .en: "Make role assignment"],
        "assignedRoles": [.ru: "Проставленные роли", .en: "Detected roles"],
        "paths": [.ru: "Пути", .en: "Paths"],
        "inputFile": [.ru: "Исходный файл", .en: "Input file"],
        "dropHint": [
            .ru: "Перетащите сюда файл субтитров или нажмите «Открыть субтитры»",
            .en: "Drop a subtitle file here or click “Open subtitles”",
        ],
        "outputFolder": [.ru: "Папка выгрузки", .en: "Output folder"],
        "source": [.ru: "Источник", .en: "Source"],
        "notSelected": [.ru: "Не выбран", .en: "Not selected"],
        "export": [.ru: "Экспорт", .en: "Export"],
        "toAss": [.ru: "В ASS", .en: "To ASS"],
        "toSrt": [.ru: "В SRT", .en: "To SRT"],
        "toVtt": [.ru: "В VTT", .en: "To VTT"],
        "toDocx": [.ru: "В DOCX", .en: "To DOCX"],
        "openFolderAfter": [.ru: "Открыть папку после обработки", .en: "Open folder after processing"],
        "closeAppAfter": [.ru: "Закрыть программу после обработки", .en: "Close app after processing"],
        "srtSettings": [.ru: "SRT", .en: "SRT"],
        "fullWithRoles": [.ru: "Полный файл с ролями в [ ]", .en: "Full file with roles in [ ]"],
        "separateByRole": [.ru: "Отдельные файлы по ролям", .en: "Separate files by role"],
        "separateWithPrefix": [.ru: "Отдельные файлы с префиксом роли", .en: "Separate files with role prefix"],
        "rolesForSeparateExport": [.ru: "Роли для раздельной выгрузки", .en: "Roles for separate export"],
        "done": [.ru: "Готово!", .en: "Done!"],
        "ok": [.ru: "OK", .en: "OK"],
        "ready": [.ru: "Готово", .en: "Ready"],
        "settings.language": [.ru: "Язык приложения", .en: "App language"],
        "qa.q1": [.ru: "Какие форматы можно импортировать?", .en: "Which formats can I import?"],
        "qa.a1": [.ru: "ASS, SSA, SRT, VTT и SRP.", .en: "ASS, SSA, SRT, VTT, and SRP."],
        "qa.q2": [.ru: "Что создаёт экспорт DOCX?", .en: "What does DOCX export create?"],
        "qa.a2": [
            .ru: "Документ с названием файла, списком ролей, таблицей таймингов/ролей/реплик и статистикой по ролям.",
            .en: "A document with the file name, role list, timing/role/dialogue table, and role statistics.",
        ],
        "qa.q3": [.ru: "Как работает разролёвка?", .en: "How does role assignment work?"],
        "qa.a3": [
            .ru: "Роли распределяются по голосам с учётом пола и количества реплик, затем роли подсвечиваются цветами Word highlight.",
            .en: "Roles are distributed across voices by gender and line count, then highlighted with Word highlight colors.",
        ],
        "qa.q4": [.ru: "Можно ли перетащить файл?", .en: "Can I drag and drop a file?"],
        "qa.a4": [.ru: "Да, перетащите файл в большую область «Исходный файл».", .en: "Yes. Drop a file into the large Input file area."],
        "imported": [.ru: "Импортировано", .en: "Imported"],
        "lines": [.ru: "реплик", .en: "lines"],
        "createdAssignment": [.ru: "Создана разролёвка", .en: "Role assignment created"],
        "outputFolderLog": [.ru: "Папка выгрузки", .en: "Output folder"],
        "createdFiles": [.ru: "Создано файлов", .en: "Created files"],
        "dropReadError": [.ru: "Не удалось прочитать путь перетащенного файла.", .en: "Could not read the dropped file path."],
        "roleAssignment": [.ru: "Разролёвка", .en: "Role assignment"],
        "close": [.ru: "Закрыть", .en: "Close"],
        "voiceCount": [.ru: "Количество голосов", .en: "Voice count"],
        "voices": [.ru: "Голоса", .en: "Voices"],
        "voice": [.ru: "Голос", .en: "Voice"],
        "highlightColor": [.ru: "Цвет выделения", .en: "Highlight color"],
        "gender": [.ru: "Пол", .en: "Gender"],
        "roles": [.ru: "Роли", .en: "Roles"],
        "lineCountSuffix": [.ru: "репл.", .en: "lines"],
        "assignRoles": [.ru: "Назначить роли", .en: "Assign roles"],
        "error.importPrefix": [.ru: "Ошибка импорта", .en: "Import error"],
        "error.exportPrefix": [.ru: "Ошибка экспорта", .en: "Export error"],
        "error.unsupportedFormat": [.ru: "Неподдерживаемый формат файла", .en: "Unsupported file format"],
        "error.invalidTime": [.ru: "Не удалось разобрать таймкод", .en: "Could not parse timecode"],
        "error.notRegularFile": [.ru: "Источник не является обычным файлом: {path}", .en: "Source is not a regular file: {path}"],
        "error.fileTooLarge": [
            .ru: "Файл слишком большой: {size} байт. Максимум: {max} байт.",
            .en: "File is too large: {size} bytes. Maximum: {max} bytes.",
        ],
        "error.noFormatSelected": [.ru: "Не выбран ни один формат экспорта.", .en: "No export format selected."],
        "error.noInputSelected": [.ru: "Сначала выберите исходный файл.", .en: "Select a source file first."],
        "error.noVoices": [.ru: "Добавьте хотя бы один голос для разролёвки.", .en: "Add at least one voice for role assignment."],
        "error.noVoiceForGender": [
            .ru: "Для ролей пола «{g}» не назначен ни один голос.",
            .en: "No voice assigned for {g} roles.",
        ],
        "error.cannotPickVoice": [.ru: "Не удалось выбрать голос для роли «{r}».", .en: "Could not pick a voice for role {r}."],
        "error.decodeFailed": [.ru: "Не удалось определить кодировку файла.", .en: "Could not detect the file encoding."],
        "role.unassigned": [.ru: "Не назначено", .en: "Unassigned"],
        "update.check": [.ru: "Проверить обновления", .en: "Check for updates"],
        "update.latest": [.ru: "У вас последняя версия.", .en: "You have the latest version."],
        "update.available": [.ru: "Доступна версия {v}.", .en: "Version {v} is available."],
        "update.download": [.ru: "Скачать", .en: "Download"],
        "error.updateFailed": [.ru: "Не удалось проверить обновления (HTTP {code}).", .en: "Update check failed (HTTP {code})."],
        "error.updateInvalidResponse": [.ru: "Не удалось разобрать ответ сервера обновлений.", .en: "Could not parse the update server response."],
        "docx.timing": [.ru: "Тайминг", .en: "Timing"],
        "docx.role": [.ru: "Роль", .en: "Role"],
        "docx.replica": [.ru: "Реплика", .en: "Line"],
        "docx.roleStats": [.ru: "Статистика по ролям", .en: "Role statistics"],
        "file.assignmentSuffix": [.ru: " [Разролёвка]", .en: " [Role assignment]"],
    ]
}
