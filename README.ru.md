<p align="center">
  <img src="Assets/AVT_helper_readme_icon.png" alt="иконка приложения AVT_helper" width="128">
</p>

<h1 align="center">AVT_helper</h1>

<p align="center">
  <strong>Язык:</strong> <a href="README.md">EN</a> | RU
</p>

<p align="center">
  <strong>конвертация субтитров и DOCX-таблицы ролей для macOS</strong>
</p>

<p align="center">
  <a href="https://github.com/boundlessend/AVT_helper/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/boundlessend/AVT_helper/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/boundlessend/AVT_helper/releases"><img alt="Latest release" src="https://img.shields.io/github/v/release/boundlessend/AVT_helper?color=2563eb"></a>
  <img alt="macOS" src="https://img.shields.io/badge/macOS-14%2B-111827">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-f05138">
  <img alt="licence" src="https://img.shields.io/badge/license-BSD--3--Clause-2563eb">
</p>

`AVT_helper` — нативное macOS-приложение для конвертации субтитров и создания DOCX-таблиц с репликами.

Приложение импортирует `ASS`, `SSA`, `SRT`, `VTT` и `SRP`, экспортирует `ASS`, `SRT`, `VTT` и `DOCX`, а также умеет делать DOCX-разролёвку с цветами выделения Word.

Окно показывает импортированный файл монтажным листом: тайминг, роль, реплика. Каждая роль подсвечена маркером, а после разролёвки лист переходит на цвета назначенных голосов, так что экран совпадает с DOCX.

Кодировка входных файлов (UTF-8, UTF-16, Windows-1251) определяется автоматически. Импорт и экспорт идут в фоне с индикатором прогресса и могут быть прерваны, поэтому окно не зависает на больших файлах.

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

> При первом запуске язык интерфейса берётся из системных настроек, переключить его можно в `Настройках` (`Cmd+,`) -> `Язык приложения`.

1. Нажмите `Открыть субтитры` (`Cmd+O`), перетащите файл на лист в центре окна или откройте файл субтитров из Finder. Последние восемь файлов лежат в `Файл` -> `Открыть недавние`.
2. Выберите папку выгрузки в левом рельсе. Она запоминается между запусками.
3. Отметьте один или несколько форматов: `ASS`, `SRT`, `VTT` или `DOCX`.
4. Отметьте нужные роли в списке справа, если выгружаете отдельные файлы SRT по ролям.
5. Нажмите `Начать` (`Cmd+Return`). Долгую операцию можно прервать кнопкой `Отменить`.
6. Чтобы создать DOCX-разролёвку, загрузите файл с ролями и нажмите `Сделать разролёвку`.

Существующие файлы не перезаписываются: к имени нового файла добавляется номер.

## DOCX

DOCX-файлы содержат название файла, список найденных ролей, таблицу таймингов/ролей/реплик и статистику по ролям. DOCX-разролёвка также показывает назначенные голоса над таблицей и выделяет назначенные роли выбранными цветами Word.

## Лицензия

BSD 3-Clause. См. [LICENSE](LICENSE).
