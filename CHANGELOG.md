# Changelog

All notable changes to `AVT_helper` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow the `v.MAJOR.MINOR.PATCH` tag scheme of this repository.

## [Unreleased]

### Added

- Check-for-updates button in the About window: it queries the latest GitHub release, reports whether a newer version exists, and offers a download link.
- The completion alert now lists the files that were created.
- A SHA-256 checksum file is published alongside the release DMG.
- Tests covering ASS and VTT import, role-to-voice balancing, timecode fraction parsing, and source-file overwrite protection.

### Changed

- Export format checkboxes and post-processing toggles persist between launches.
- DOCX table headers, role statistics, and voice summaries follow the app language instead of being Russian-only.
- The "Unassigned" role label and the role-assignment file suffix follow the app language.
- The drop zone highlights while a file is dragged over it.
- Shared window header component reused across the Q&A, Settings, and role assignment windows.
- Release workflow runs the test suite before building the DMG; CI lints `Tests` and no longer runs twice per pull request.
- The app bundle declares the Utilities category; `codesign` no longer uses the deprecated `--deep` flag.

### Fixed

- Exporting ASS or VTT into the folder of the imported file could silently overwrite the source; such exports now receive a ` (1)` name suffix.
- Single-digit fractions in timecodes were read as raw milliseconds (`,5` now parses as 500 ms), and SRT timecodes accept a dot separator.
- Commas in ASS style and actor fields no longer break exported `Dialogue:` lines.
- Removed the dead "Reset app cache" button that cleaned temporary files no longer produced by the app.
- Role replica counts were recomputed on every render of the role assignment sheet.

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
