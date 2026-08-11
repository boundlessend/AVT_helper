# Changelog

All notable changes to `AVT_helper` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow the `v.MAJOR.MINOR.PATCH` tag scheme of this repository.

## [Unreleased]

### Added

- Check-for-updates button in the About window: it queries the latest GitHub release, reports whether a newer version exists, and offers a download link.
- The completion alert now lists the files that were created, caps a long list and offers `Show in Finder`.
- A SHA-256 checksum file is published alongside the release DMG.
- Progress bar with a percentage and a `Cancel` button for import and export.
- `Open subtitles` in the `File` menu under `Cmd+O`; settings moved to a `Settings` scene reachable with `Cmd+,`.
- Message log behind a click on the status bar, so an error stays readable after the next event.
- Tests covering ASS, VTT and SRP import, DOCX content and validity, role-to-voice balancing, timecode fraction parsing, output name collisions, progress and cancellation, and version comparison.

### Changed

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

[unreleased]: https://github.com/boundlessend/AVT_helper/compare/v.1.6.5...HEAD
[1.6.5]: https://github.com/boundlessend/AVT_helper/compare/v.1.6.0...v.1.6.5
[1.6.0]: https://github.com/boundlessend/AVT_helper/compare/v.1.5.0...v.1.6.0
[1.5.0]: https://github.com/boundlessend/AVT_helper/compare/v.1.0.0...v.1.5.0
[1.0.0]: https://github.com/boundlessend/AVT_helper/releases/tag/v.1.0.0
