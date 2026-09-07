# Changelog

All notable changes to `AVT_helper` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow the `v.MAJOR.MINOR.PATCH` tag scheme of this repository.

## [Unreleased]

## [1.8.0] - 2026-09-01

### Fixed

- **A timecode outside the range of an integer killed the app.** Sixteen digits in the hours field overflowed on the way to milliseconds and took the process with them, while a negative component was quietly clamped to zero instead of being refused. Every component is checked before it is converted, and a cue whose end comes before its start is dropped like any other damaged block.
- **A line made of spaces or tabs did not count as a blank line**, so two cues of an `SRT` or `VTT` file glued into one. Whitespace-only lines separate blocks now.
- **Lines with the same timecode came out in a different order every run**, which shuffled the parts of a chorus line. When the timecodes match, the source order decides.
- **An `SRP` that declares `windows-1251` in its prolog arrived as mojibake.** The text had already been decoded by then, and the parser read those bytes a second time according to the declaration. The declaration is removed before parsing.
- **Part of a file could be lost in silence.** Blocks the importer could not parse are counted, and the number is reported next to the number of lines, so a half-read file no longer looks like a file that never had those lines.
- **ASS export pointed at styles that were not in the file.** The `[Script Info]` and `[V4+ Styles]` blocks of the source are now carried over, so style names resolve and the frame size survives the round trip. A line whose style is not declared falls back to `Default` instead of naming a style no player can find, and a `[V4 Styles]` block of an `SSA` source is converted to v4+ rather than left beside v4+ events.
- **The `Format:` line of `[Events]` was ignored** and the field order assumed. A file that declares its own order now imports correctly, and an order that does not end with `Text` is refused with a message instead of importing shifted fields.
- **`ASS` export replaced `Layer`, the margins and `Effect` with zeros**, so positioned signs and karaoke lost what held them in place. The values of the source line are written back.
- **A backslash or a curly brace in the dialogue did not survive the round trip.** Both are escaped on the way out and unescaped on the way in, in one pass, so `\\n` from an escaped backslash is no longer read as a line break.
- **`WebVTT` text went out unescaped.** An ampersand, an angle bracket or a stray `-->` inside a line produced a file that players read as markup.
- **A blank line inside a line of dialogue split the block.** The `\N\N` of the source ended the cue early, and everything after it silently disappeared when the file was read back.
- **The `Unassigned` label travelled into the exported text** and came back from the next import as a real role with that name.
- **An interrupted write left a truncated file under a name that was already taken.** Subtitles and DOCX go to a temporary file beside the target and are renamed into place, so a name holds either a whole file or no file at all.
- **A very long role name broke the export mid-run** by producing a file name past the file system limit. The assembled name is truncated on a character boundary with room left for the extension and the numbered suffix, and an export that cannot find a free name after a thousand tries says so instead of trying forever.
- **Separate `SRT` files with nothing to write reported the wrong reason.** An export whose only format is separate files by role, with no selected role that has any lines, said that no format was selected. It now names the roles as the cause.
- **DOCX broke the rules of its own format.** The children of `w:rPr` went out in an order the schema does not allow, the table header did not repeat when the table crossed a page, the document declared no language so Word spell-checked Russian lines against the wrong dictionary, and every archive entry carried an impossible MS-DOS date of month zero and day zero.
- **An interrupted import threw away the file already on screen.** Cancelling or failing to read a second file leaves the first one loaded, a cancelled import keeps its file in the queue, and after a failed import the selection points at the file that is actually on screen instead of one that has been removed.
- **A failed export said nothing about the files it had already written.** The error names them and they are listed in the completion alert; a cancelled run reports them the same way instead of losing the whole account of itself.
- **DOCX carried no role colors unless a role assignment had been made**, although the window showed them and the README promised the two would match. The colors of the sheet now reach every DOCX.
- **A line spoken by several characters was highlighted with one color.** Every role of a chorus line keeps the color of its own voice.
- **UTF-16 files without a byte order mark decoded into text full of holes**, because a zero byte is valid UTF-8. Encodings are now sniffed and each candidate is inspected before it is accepted; a file that decodes into nothing readable is refused instead of arriving as a file with no dialogue lines.
- **`Cmd+Q` in the middle of a run killed the writing.** Quitting while files are being written asks first, and the answer that keeps working is the default one.
- **Dropping a file while the app was busy broke the `Cancel` button.** Every way in - the menu, the panel and the drop zone - refuses while a run is going and says why.
- **The panel for choosing files blocked the whole app** while it was open. It is a sheet now, and one `Cmd+O` opens one panel however many windows are around.
- **Switching the interface language wiped a finished role assignment.** Only the `Unassigned` label is renamed, and the voices and colors move with it.
- **The role assignment could not be stopped while it wrote the DOCX.** The same `Cancel` button stops the writing first and closes the sheet after.
- **A relaunch after a language change quit before the new copy had started**, so a failed launch left no app at all. It waits for the new copy, and a failure is reported in the settings window.
- **The role checkboxes still held the roles of the previous file** after another file of the queue was selected, and an export of separate files by role found nothing to write. They follow the file on screen.
- **The ninth role was painted with the color of the first.** Eight highlight colors is the whole palette, so roles past the eighth get no color rather than one that cannot be told apart.
- **The `Unassigned` label took a voice and a color of its own in the role assignment**, although it is a substituted label rather than a role. It is left out, as it already was in the automatic coloring.
- **A missing translation reached the user as the raw key.** The assertion meant to catch it is stripped from a release build, so the text of the other language is shown instead, and a placeholder is no longer substituted into text that another value had just inserted.
- **An output folder without write permission passed the check** and the run failed halfway through with a raw Cocoa error. Writability is part of the check.
- **The role prefix setting switched separate `SRT` files back on at every launch**, undoing the checkbox the user had cleared. The nested setting is switched off instead of reviving its parent.
- **The status bar showed a hint about the message log where the message belonged.** A status trimmed to two lines is readable in full on hover.
- Russian counts had a single form everywhere: "1 реплик", "2 реплик". Numbers of lines, roles, files and skipped blocks now decline properly through `.stringsdict`.
- The file size in the too-large error is stated in megabytes rather than bytes.
- Voices could be raised to twelve while only eight highlight colors exist, so the duplicate-color warning could not be dismissed. Eight is the ceiling.
- `Cmd+Return` was declared twice, on the `Start` button and on its menu item, and the two competed for the keystroke. The menu item owns it.
- DOCX files no longer carry the author of the program or the name of the producing application in their properties: `docProps/app.xml` is not written at all.

### Changed

- **A queue of files.** Several files can be opened or dropped at once; `Start` runs the whole queue with the same export settings and marks each file with what came of it. The sheet shows the file you pick. Role assignment stays per file.
- **The queue is a list rather than a stack of buttons.** The selection moves with the arrow keys, `Delete` removes the selected file, and the state of each file is spoken by VoiceOver instead of being carried by the color of an icon alone.
- **The app language now moves the menus with it.** The choice is written to `AppleLanguages`, and the app offers to relaunch so that menus, the open panel and system buttons speak the same language as the window. A third option, `Same as system`, was added.
- `Start` and `Make role assignment` are in a `Process` menu with keyboard shortcuts, `Check for Updates…` is in the app menu, `Q&A` moved to the `Help` menu, and the `Window` menu can bring the main window back after it has been closed.
- `Open Recent` lists the files the app has opened, with `Clear Menu` at the bottom. The list is the system one kept by `NSDocumentController`, so it follows a renamed file and survives a reinstall. It starts empty once, because the old list was private to the app.
- The app checks for a new version once a week in the background, with a switch in settings. The request carries an `ETag`, a `User-Agent` and a timeout, so an unchanged release costs nothing against the hourly limit of GitHub; a check that fails counts as an attempt and is retried in an hour rather than on every launch, and a secondary rate limit is recognized as one. It still downloads nothing by itself.
- The settings window is a grouped form with the title drawn by the system, as macOS settings are.
- Columns of the main window are draggable, so the dialogue column is no longer squeezed by two fixed rails.
- The status bar names why `Start` is unavailable instead of hiding it in a tooltip, and the message log behind it is marked with an icon.
- The role checkboxes are disabled unless separate files by role are on, and the hint says so.
- The output folder is applied when editing of the path ends, not on every keystroke.
- Voices of a role assignment persist between runs, roles can be set to one gender in a click, and the sheet's buttons sit at the bottom with `Cancel` on Escape. A source that carries no gender of its own, which is everything but `SRP`, gets male and female by turns instead of a cast that is male to the last role.
- Gender names and the names of the highlight colors follow the app language.
- The export format buttons use the system accent color, and text set in capitals is styled rather than uppercased, so VoiceOver reads names as names.
- Dropping a file the app cannot read no longer highlights the drop zone first and complains after.
- Subtitles and DOCX are written to disk as they are built, so a long file no longer exists twice: once as text in memory and once on disk.
- The bundle declares its subtitle types properly (`LSItemContentTypes` and imported UTIs, `SRT` among them), carries a real copyright string, explains in the system prompt why it wants the Desktop, Documents and Downloads folders, takes its minimum system version from `Package.swift`, and no longer allows sudden termination while files are being written.
- The controls that appeared in more than one place - `Close`, `Check for Updates…`, the section headers and the progress readout - are one view each, so the copies can no longer drift apart.
- The package is `swift-tools-version: 6.0` and the app is built in the Swift 6 language mode, so a concurrency violation is a compile error instead of a warning.
- The disk image carries the version in its volume name and is mounted and inspected right after it is built, so a broken image fails on the build machine rather than on somebody's desk.
- CI builds and tests on macOS 14 as well as macOS 15, lints through `scripts/lint.sh` with the rules written down instead of taken from whatever `swift-format` was at hand, and pins every action to a commit. The release build checks the version inside the bundle against the tag and refuses a bundle that is not marked as a release.
- The SwiftPM cache step was dropped from CI: there are no dependencies to cache.
- `run_app.command` quits a running copy before it starts the freshly built one, because `open` would only bring the old one forward.

### Security

- **The update check opened whatever address the answer named.** The page address arrived over the network and went to the system opener as it was, in any scheme it liked, `file://` included. Only `https` on `github.com` and its subdomains is opened now.
- **A small `SRP` could expand into gigabytes of memory before it was refused.** Internal entities were expanded while the document was being constructed, and the check for a `DTD` ran only after that. The `DOCTYPE` is found in the text first, so an expansion bomb never reaches the parser.
- The release workflow no longer leaves its token in `.git/config` where every later step of the build could read it, and write permission is granted to the job that publishes the release instead of to the whole workflow.

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
