<p align="center">
  <img src="Assets/AVT_helper_readme_icon.png" alt="AVT_helper app icon" width="128">
</p>

<h1 align="center">AVT_helper</h1>

<p align="center">
  <strong>Language:</strong> EN | <a href="README.ru.md">RU</a> | <a href="README.fr.md">FR</a>
</p>

<p align="center">
  <strong>macOS subtitle conversion and DOCX role tables</strong>
</p>

<p align="center">
  <a href="https://github.com/boundlessend/AVT_helper/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/boundlessend/AVT_helper/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/boundlessend/AVT_helper/actions/workflows/release.yml"><img alt="Release DMG" src="https://github.com/boundlessend/AVT_helper/actions/workflows/release.yml/badge.svg"></a>
  <img alt="macOS" src="https://img.shields.io/badge/macOS-14%2B-111827">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-f05138">
  <img alt="licence" src="https://img.shields.io/badge/license-BSD--3--Clause-2563eb">
</p>

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

> The app launches in Russian by default. Switch the language in `Settings` -> `App language`.

1. Click `Open subtitles` or drag a subtitle file into the input area.
2. Choose the output folder.
3. Select one or more export formats: `ASS`, `SRT`, `VTT`, or `DOCX`.
4. Click `Start`.
5. To create a role-assignment DOCX, load a file with roles and click `Make role assignment`.

## DOCX Output

DOCX files include the file name, detected roles, a timing/role/dialogue table, and role statistics. Role-assignment DOCX files also list assigned voices above the table and highlight assigned roles with the selected Word highlight colors.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
