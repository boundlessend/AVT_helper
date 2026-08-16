# Changelog

All notable changes to `AVT_helper` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow the `v.MAJOR.MINOR.PATCH` tag scheme of this repository.

## [Unreleased]

### Fixed

- **ASS export pointed at styles that were not in the file.** The `[Script Info]` and `[V4+ Styles]` blocks of the source are now carried over, so style names resolve and the frame size survives the round trip. A line whose style is not declared falls back to `Default` instead of naming a style no player can find.
- **An interrupted import threw away the file already on screen.** Cancelling or failing to read a second file now leaves the first one loaded.
- **A failed export said nothing about the files it had already written.** The error names them and they are listed in the completion alert.
- **DOCX carried no role colors unless a role assignment had been made**, although the window showed them and the README promised the two would match. The colors of the sheet now reach every DOCX.
- **A line spoken by several characters was highlighted with one color.** Every role of a chorus line keeps the color of its own voice.
- **UTF-16 files without a byte order mark decoded into text full of holes**, because a zero byte is valid UTF-8. Encodings are now sniffed and each candidate is inspected before it is accepted; a file that decodes into nothing readable is refused instead of arriving as a file with no dialogue lines.
- **A very long role name broke the export mid-run** by producing a file name past the file system limit. Names are truncated on a character boundary.
- **The `Format:` line of `[Events]` was ignored** and the field order assumed. A file that declares its own order now imports correctly.
- Russian counts had a single form everywhere: "1 реплик", "2 реплик". Numbers of lines, roles and files now decline properly through `.stringsdict`.
- The file size in the too-large error is stated in megabytes rather than bytes.
- Voices could be raised to twelve while only eight highlight colors exist, so the duplicate-color warning could not be dismissed. Eight is the ceiling.
- DOCX files no longer carry the author of the program in their properties.

### Changed

- **A queue of files.** Several files can be opened or dropped at once; `Start` runs the whole queue with the same export settings and marks each file with what came of it. The sheet shows the file you pick. Role assignment stays per file.
- **The app language now moves the menus with it.** The choice is written to `AppleLanguages`, and the app offers to relaunch so that menus, the open panel and system buttons speak the same language as the window. A third option, `Same as system`, was added.
- `Start` and `Make role assignment` are in a `Process` menu with keyboard shortcuts, `Check for Updates…` is in the app menu, `Q&A` moved to the `Help` menu, and the `Window` menu can bring the main window back after it has been closed.
- The app checks for a new version once a week in the background, with a switch in settings. It still downloads nothing by itself.
- The settings window is a grouped form with the title drawn by the system, as macOS settings are.
- Columns of the main window are draggable, so the dialogue column is no longer squeezed by two fixed rails.
- The status bar names why `Start` is unavailable instead of hiding it in a tooltip, and the message log behind it is marked with an icon.
- The role checkboxes are disabled unless separate files by role are on, and the hint says so.
- `Open Recent` is the system menu from `NSDocumentController`, with icons and `Clear Menu`. The list starts empty once, because the old one was kept privately.
- Voices of a role assignment persist between runs, roles can be set to one gender in a click, and the sheet's buttons sit at the bottom with `Cancel` on Escape.
- The export format buttons use the system accent color, and text set in capitals is styled rather than uppercased, so VoiceOver reads names as names.
- Dropping a file the app cannot read no longer highlights the drop zone first and complains after.
- The bundle declares its subtitle types properly (`LSItemContentTypes` and imported UTIs), carries a real copyright string, and no longer allows sudden termination while files are being written.
- The controls that appeared in more than one place - `Close`, `Check for Updates…`, the section headers and the progress readout - are one view each, so the copies can no longer drift apart.
- The design mockups moved to `docs/design`.
- The SwiftPM cache step was dropped from CI: there are no dependencies to cache.

## [1.7.0] - 2026-08-12

### Added

- Check-for-updates button in the About window: it queries the latest GitHub release, reports whether a newer version exists, and offers a download link.
- The completion alert now lists the files that were created, caps a long list and offers `Show in Finder`.
- A SHA-256 checksum file is published alongside the release DMG.
- Progress bar with a percentage and a `Cancel` button for import and export.
- `Open subtitles` in the `File` menu under `Cmd+O`; settings moved to a `Settings` scene reachable with `Cmd+,`.
- Message log behind a click on the status bar, so an error stays readable after the next event.
- Tests covering ASS, VTT and SRP import, DOCX content and validity, role-to-voice balancing, timecode fraction parsing, output name collisions, progress and cancellation, and version comparison.

### Security

- SRP import resolved external XML entities, so a crafted file could read local files and carry their contents into the exported DOCX. Files that declare a DTD are refused.

### Changed

- Subtitle files open from Finder and the `File` menu lists the last eight of them.
- The WebVTT voice tag `<v Name>` is read as a role, and markup tags no longer end up in the dialogue text.
- A line spoken by several characters keeps all of them in ASS: the names are joined with a pipe and split back on import.
- Assigned voices are named in the role list, so the voice no longer depends on telling eight highlight colors apart.
- The role column of the sheet grows with the window instead of cutting names at a fixed width.
- `Start` moved to `Cmd+Return` so that Enter in the output path field no longer launches a run.
- The role prefix became an option of the separate SRT files instead of a second checkbox that produced the same one set.
- Interface texts moved from a Swift dictionary into `ru.lproj` and `en.lproj` resources; a missing key now trips an assertion instead of showing the key.
- `CFBundleVersion` is the commit count and grows between builds; the About window reports the build and its origin.
- The app target is compiled with strict concurrency checking.
- The main window was rebuilt around the imported file: a left rail holds the output settings, the middle shows the file as a dubbing sheet of timecode, role and line, and the role list moved to a right column with per-role share bars.
- Roles carry a marker color everywhere: assigned automatically after import, replaced by the color of the assigned voice after a role assignment, so the screen matches the DOCX.
- Role assignment previews which voice every role will get while the voices are being set up, and reports the roles of each voice in its table.
- Export format checkboxes and post-processing toggles persist between launches; SRT is enabled by default.
- The output folder is remembered between launches.
- DOCX table headers, role statistics, and voice summaries follow the app language instead of being Russian-only.
- The "Unassigned" role label and the role-assignment file suffix follow the app language.
- The two role lists became one list with a checkbox and a line count per role, plus `All` / `None` buttons; an empty selection now means no separate files instead of all of them.
- `Start` is disabled with the reason in its tooltip when no file or no export format is chosen.
- On first launch the interface follows the system language.
- Role assignment reports its errors inside the sheet, warns about duplicate highlight colors, and refuses to run while a gender has no voice.
- DOCX packages are compressed with deflate instead of being stored uncompressed.
- The drop zone highlights while a file is dragged over it and uses `dropDestination`.
- Release workflow lints, runs the test suite before building the DMG and refuses to publish a tag without a matching changelog section; CI no longer runs twice per pull request.
- The app icon is generated from a single source image during the build instead of being committed as ten slices.
- Builds outside a release tag carry a `-dev.<sha>` suffix in the displayed version.
- The app bundle declares the Utilities category; `codesign` no longer uses the deprecated `--deep` flag.
- The French README is gone: the interface itself is only Russian and English.

### Fixed

- A file that spelled one role differently in different lines ("Анна" and "АННА") showed it as one role with a fraction of its lines, a wrong share bar and a marker on only part of the sheet. Role spelling is unified at import.
- Square brackets in the middle of a line, which is how stage directions are written, became role names.
- Role assignment ran with a missing output folder and failed with a raw Cocoa error; the button now explains itself and the run refuses politely.
- The role assignment preview swallowed its error, leaving the colors blank without a reason.
- The progress bar could jump backwards because each percent arrived as its own task.
- The update check reported a bare `HTTP 403` when GitHub refused it over the hourly request limit.
- Exporting into a folder that already holds files with the same names silently replaced them, and two roles whose names collapse to the same file name wrote into a single file; both cases now get a numbered suffix.
- Control characters in dialogue produced a DOCX that Word refuses to open.
- Role assignment errors went to the status bar of the main window, hidden behind the sheet.
- The "Unassigned" label was frozen at import time and stayed in the import-time language.
- The update check compared versions as strings, so it reported an update for any difference and would have called `1.10.0` older than `1.9.9`.
- Curly braces in dialogue are escaped for ASS, so text that contains them survives a round trip.
- A file that parses into zero lines is an import error instead of producing empty exports.
- Single-digit fractions in timecodes were read as raw milliseconds (`,5` now parses as 500 ms), and SRT timecodes accept a dot separator.
- Commas in ASS style and actor fields no longer break exported `Dialogue:` lines.
- Removed the dead "Reset app cache" button that cleaned temporary files no longer produced by the app.
- Role names are normalized once at import instead of on every access, which removed a per-role pass over every line during export.

## [1.6.5] - 2026-06-28

### Added

- Automatic input encoding detection (UTF-8, UTF-16, Windows-1251) instead of assuming UTF-8.
- Test target with core coverage, run in CI together with `swift-format` lint.
- Editable output path field.

### Changed

- Import and export run off the main thread with progress indicators, keeping the window responsive on large files.
- DOCX is written with a native in-memory ZIP writer (no temporary folders).
- DMG is built with native `hdiutil` instead of the `create-dmg` package.
- Error messages are localized by the current app language.
- App version is derived from the git tag.

## [1.6.0] - 2026-06-08

### Added

- English, Russian, and French READMEs with install guides.
- SRP sex metadata used as a role gender hint during role assignment.
- Release workflow that packages an ad-hoc signed app into a DMG.

### Changed

- Import hardened: directories and files larger than 50 MB are rejected.
- License switched from MIT to BSD 3-Clause.
- App quits when the last window closes.

## [1.5.0] - 2026-05-07

### Added

- Voice assignment summary block in the role-assignment DOCX export.

## [1.0.0] - 2026-05-07

### Added

- Initial macOS app: imports ASS, SSA, SRT, VTT, and SRP; exports ASS, SRT, VTT, and DOCX dialogue tables with role assignment and Word highlight colors.

[unreleased]: https://github.com/boundlessend/AVT_helper/compare/v.1.7.0...HEAD
[1.7.0]: https://github.com/boundlessend/AVT_helper/compare/v.1.6.5...v.1.7.0
[1.6.5]: https://github.com/boundlessend/AVT_helper/compare/v.1.6.0...v.1.6.5
[1.6.0]: https://github.com/boundlessend/AVT_helper/compare/v.1.5.0...v.1.6.0
[1.5.0]: https://github.com/boundlessend/AVT_helper/compare/v.1.0.0...v.1.5.0
[1.0.0]: https://github.com/boundlessend/AVT_helper/releases/tag/v.1.0.0
