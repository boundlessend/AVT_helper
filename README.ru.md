![иконка AVT_helper](Assets/AVT_helper_icon.png)

Язык: [EN](README.md) | RU | [FR](README.fr.md)

# AVT_helper

[![CI](https://github.com/boundlessend/AVT_helper/actions/workflows/ci.yml/badge.svg)](https://github.com/boundlessend/AVT_helper/actions/workflows/ci.yml)
[![Release DMG](https://github.com/boundlessend/AVT_helper/actions/workflows/release.yml/badge.svg)](https://github.com/boundlessend/AVT_helper/actions/workflows/release.yml)
![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![License](https://img.shields.io/badge/License-BSD--3--Clause-green)

`AVT_helper` — нативное macOS-приложение для конвертации субтитров и создания DOCX-таблиц с репликами.

Приложение импортирует `ASS`, `SSA`, `SRT`, `VTT` и `SRP`, экспортирует `ASS`, `SRT`, `VTT` и `DOCX`, а также умеет делать DOCX-разролёвку с цветами выделения Word.

## Установка

1. Скачайте `AVT_helper.dmg` из последнего релиза.
2. Откройте `AVT_helper.dmg`.
3. Перетащите `AVT_helper.app` в `Applications`.
4. Запустите `AVT_helper.app` из `Applications`.

Если macOS заблокирует первый запуск, выполните:

```bash
sudo xattr -rd com.apple.quarantine "/Applications/AVT_helper.app"
```

После этого откройте приложение снова.

## Использование

1. Нажмите `Открыть субтитры` или перетащите файл в область исходного файла.
2. Выберите папку выгрузки.
3. Отметьте один или несколько форматов: `ASS`, `SRT`, `VTT` или `DOCX`.
4. Нажмите `Начать`.
5. Чтобы создать DOCX-разролёвку, загрузите файл с ролями и нажмите `Сделать разролёвку`.

## DOCX

DOCX-файлы содержат название файла, список найденных ролей, таблицу таймингов/ролей/реплик и статистику по ролям. DOCX-разролёвка также показывает назначенные голоса над таблицей и выделяет назначенные роли выбранными цветами Word.

## Лицензия

BSD 3-Clause. См. [LICENSE](LICENSE).
