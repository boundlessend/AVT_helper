<p align="center">
  <img src="Assets/AVT_helper_readme_icon.png" alt="AVT_helper app icon" width="128">
</p>

<h1 align="center">AVT_helper</h1>

<p align="center">
  <strong>Language:</strong> EN | <a href="README.ru.md">RU</a>
</p>

<p align="center">
  <strong>macOS subtitle conversion and DOCX role tables</strong>
</p>

<p align="center">
  <a href="https://github.com/boundlessend/AVT_helper/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/boundlessend/AVT_helper/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/boundlessend/AVT_helper/releases"><img alt="Latest release" src="https://img.shields.io/github/v/release/boundlessend/AVT_helper?color=2563eb"></a>
  <img alt="macOS" src="https://img.shields.io/badge/macOS-14%2B-111827">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-f05138">
  <img alt="licence" src="https://img.shields.io/badge/license-BSD--3--Clause-2563eb">
</p>

`AVT_helper` is a native macOS app for subtitle conversion and DOCX dialogue tables.

It imports `ASS`, `SSA`, `SRT`, `VTT`, and `SRP`, exports `ASS`, `SRT`, `VTT`, and `DOCX`, and can create role-assignment DOCX files with Word highlight colors.

The window shows the imported file as a dubbing sheet: timecode, role, line. Every role is highlighted with a marker color, and after a role assignment the sheet switches to the colors of the assigned voices, so the screen matches the DOCX.

Input encoding (UTF-8, UTF-16, Windows-1251) is detected automatically. Import and export run in the background with a progress bar and can be cancelled, so the window stays responsive on large files.

## Install

1. Download `AVT_helper.dmg` from the latest release.
2. Open `AVT_helper.dmg`.
3. Drag `AVT_helper.app` to `Applications`.
4. The build is signed but not notarized, so Gatekeeper blocks the first launch. Open it this way once: **right click** (or Control-click) the app in `Applications` and choose **Open**, then confirm in the dialog. If macOS still refuses, go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.

After the first launch macOS remembers the choice and opens the app normally.

If the app is reported as damaged, the quarantine flag is the cause. Clear it once in Terminal, without `sudo`: the app belongs to you after the copy.

```bash
xattr -dr com.apple.quarantine "/Applications/AVT_helper.app"
```

## Usage

> The interface follows the system language. Pick a different one in `Settings` (`Cmd+,`) -> `App language`; menus and system panels follow after the relaunch the app offers.

1. Click `Open subtitles` (`Cmd+O`), drop subtitle files onto the sheet in the middle of the window, or open them from Finder. Recent files are under `File` -> `Open Recent`.
2. Choose the output folder in the left rail. It is remembered between launches.
3. Select one or more export formats: `ASS`, `SRT`, `VTT`, or `DOCX`.
4. Check the roles you need in the role list on the right if you export separate SRT files per role.
5. Click `Start` (`Cmd+Return`, also in the `Process` menu). A long run can be stopped with `Cancel`.
6. To create a role-assignment DOCX, load a file with roles and click `Make role assignment` (`Cmd+Shift+R`).

Existing files are never overwritten: a numbered suffix is added to the new file instead.

### A queue of files

Drop or open several files at once and they queue up in the left rail. `Start` runs the whole queue with the same export settings, marking every file with what came of it. The sheet shows the file you select; the role checkboxes belong to that file, and the other files export all of their own roles. Role assignment stays per file, because every episode has its own cast.

### What ASS export keeps

The `[Script Info]` and `[V4+ Styles]` blocks of the source file are carried over, so style names still resolve and the frame size survives. Inline override tags inside a line (`{\i1}` and the like) are dropped at import: the window shows a dubbing sheet, not typesetting. Lines whose style is not declared in the file fall back to `Default` rather than pointing at a style that does not exist.

## DOCX Output

DOCX files include the file name, detected roles, a timing/role/dialogue table, and role statistics. Role-assignment DOCX files also list assigned voices above the table and highlight assigned roles with the selected Word highlight colors.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
