![AVT_helper icon](Assets/AVT_helper_icon.png)

Language: EN | [RU](README.ru.md) | [FR](README.fr.md)

# AVT_helper

[![CI](https://github.com/boundlessend/AVT_helper/actions/workflows/ci.yml/badge.svg)](https://github.com/boundlessend/AVT_helper/actions/workflows/ci.yml)
[![Release DMG](https://github.com/boundlessend/AVT_helper/actions/workflows/release.yml/badge.svg)](https://github.com/boundlessend/AVT_helper/actions/workflows/release.yml)
![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![License](https://img.shields.io/badge/License-BSD--3--Clause-green)

`AVT_helper` is a native macOS app for subtitle conversion and DOCX dialogue tables.

It imports `ASS`, `SSA`, `SRT`, `VTT`, and `SRP`, exports `ASS`, `SRT`, `VTT`, and `DOCX`, and can create role-assignment DOCX files with Word highlight colors.

## Install

1. Download `AVT_helper.dmg` from the latest release.
2. Open `AVT_helper.dmg`.
3. Drag `AVT_helper.app` to `Applications`.
4. Open `AVT_helper.app` from `Applications`.

If macOS blocks the first launch, run:

```bash
sudo xattr -rd com.apple.quarantine "/Applications/AVT_helper.app"
```

Then open the app again.

## Usage

1. Click `Open subtitles` or drag a subtitle file into the input area.
2. Choose the output folder.
3. Select one or more export formats: `ASS`, `SRT`, `VTT`, or `DOCX`.
4. Click `Start`.
5. To create a role-assignment DOCX, load a file with roles and click `Make role assignment`.

## DOCX Output

DOCX files include the file name, detected roles, a timing/role/dialogue table, and role statistics. Role-assignment DOCX files also list assigned voices above the table and highlight assigned roles with the selected Word highlight colors.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
