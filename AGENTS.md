# AGENTS.md

Guide file for AI coding agents working in this repository.

Every rule below traces to a mistake that has already happened here. Add a rule only after
observing a failure, date it, and delete it once a test enforces the same thing. A rule that
cannot be checked without subjective judgement does not belong in this file.

## Project facts

| | |
|---|---|
| Product | `AVT_helper`, a native macOS subtitle converter and DOCX role-table generator |
| Language | Swift 6, SwiftUI, AppKit where SwiftUI has no equivalent |
| Build system | SwiftPM only. There is no Xcode project and none should be added |
| Platform | macOS 14+, `defaultLocalization: "ru"`, ships `ru` and `en` |
| Concurrency | `swift-tools-version: 6.0` and `swiftLanguageMode(.v6)`: a data race is a compile error |
| Tag scheme | `v.MAJOR.MINOR.PATCH`, with the dot after `v` (`v.1.7.0`) |

## Commands

Run all three before reporting a change as done.

```bash
./scripts/lint.sh        # swift format lint --strict, so a warning fails
swift build -c release
swift test
```

Packaging, which CI also runs on every commit, so a broken script fails the build rather than
the release:

```bash
./scripts/build_app.sh   # writes .build/AVT_helper.app, ad-hoc signed
./scripts/build_dmg.sh   # calls build_app.sh, then hdiutil, and mounts the image to check it
```

CI additionally guards this file and the changelog: `## [Unreleased]` must exist in
`CHANGELOG.md`, and every test named in the table below must still exist in `Tests`. Rename a
test and this file has to be updated with it. The guard reads any word starting with `test` and
a capital letter, so do not write one in prose unless it is a real test. It also refuses a file
that names fewer than ten of them: an emptied table would leave the guard checking nothing.

## Conventions

- Comments and docstrings: Russian, lower case, no trailing dot. This holds in shell scripts too.
- Markdown, commit messages, `CHANGELOG.md` and UI source keys: English. `README.ru.md` is the
  only translated document, and it must stay in step with `README.md`.
- Commits follow Conventional Commits with an English scope and description.
- `.swift-format` sets 4 spaces and a line length of 140. Do not reformat code the change does
  not touch: the linter is strict and an unrelated reflow buries the real diff.

## Rules

**No user-visible string is a literal.** Every text goes through `L.text`, `L.plural`,
`L.format` or a view's private `t(_:)`, with the key present in both `ru.lproj` and `en.lproj`.
Counts go through `.stringsdict`, never string interpolation: Russian needs three forms and the
rule for 11-14 differs from the rule for 1-4. Added 2026-08-12, after the interface texts were
moved out of the source and the Russian counts read "1 реплик".

**A keyboard shortcut has exactly one owner, and it is the menu item.** Declaring the same
shortcut on a button and on its menu item makes the two compete for the keystroke, and macOS
then stops printing it beside the menu entry. The button declares none and stays a plain button.
Added 2026-08-16, after `Cmd+Return` was declared on both `Start` and its menu item.

**Never create the output folder.** `OutputFolder.isUsable` gates the run in the interface;
the exporter must not call `createDirectory`. Creating it turns a typo in the path into a
silent pile of files somewhere nobody will look. Added 2026-08-16.

**Bundle metadata comes from git, not from the clock.** `CFBundleVersion` is the commit count
so it grows monotonically, and the copyright year is the date of the last commit. Rebuilding an
old tag must produce the same bundle. Do not replace either with `date`. Added 2026-08-12.

**Concurrency violations get fixed, not silenced.** No `@unchecked Sendable` to quiet the
compiler. The Swift 6 language mode is on, so these are errors and there is nothing to postpone.
Added 2026-08-12, tightened 2026-09-01 when the experimental flag became the language mode.

**A block the importer could not parse is counted and the count reaches the user.** The parser
returns `skippedBlocks`, and the import line in the message log names it through `import.skipped`
and `count.blocks`. A file that quietly loses half of itself looks to the user like a file that
never had those lines. Added 2026-09-01.

**The resource bundle is found through `Bundle.main.resourceURL`, not `Bundle.module`.** SwiftPM generates an accessor that looks beside the executable's bundle, which for a `.app` means beside the `.app` itself, and the fallback it writes is the build directory of whoever compiled it. That fallback hides the failure on the machine that built the app and breaks it everywhere else. `scripts/build_app.sh` refuses a bundle without `ru.lproj` and launches the app once before reporting success. Added 2026-09-07, after 1.8.0 shipped an app that died on the first localized string.

**Every user-visible change gets a `CHANGELOG.md` entry under `## [Unreleased]` in the same
commit.** The release workflow refuses to build a DMG when the tag has no matching
`## [MAJOR.MINOR.PATCH]` heading, and that heading is produced by renaming `## [Unreleased]`.

**The app is signed ad-hoc and deliberately not notarized.** Do not add notarization or
stapling steps, and do not remove the `xattr -dr com.apple.quarantine` instruction from either
README: it is what makes the DMG usable.

## Invariants already under test

These are enforced by `Tests/AVT_helperTests`. Change the behaviour only as a deliberate
decision, never by relaxing the test that guards it.

| Invariant | Test |
|---|---|
| Export never overwrites an existing file or its own source, across runs | `testExportDoesNotOverwriteSourceFile`, `testSecondExportKeepsEarlierFiles` |
| Encodings are sniffed and the decoded text inspected; UTF-16 without a BOM is not read as UTF-8 | `testImportsUtf16WithoutBom`, `testRejectsUndecodableFile` |
| SRP import rejects external entities | `testSrpRejectsExternalEntities` |
| ASS keeps source headers, honours the declared `Format:` order, and falls back to `Default` for an undeclared style | `testAssExportKeepsSourceStyles`, `testAssHonoursDeclaredFieldOrder`, `testAssExportFallsBackToDeclaredStyle` |
| Every role of a chorus line keeps its own colour | `testChorusLineKeepsColorOfEveryRole`, `testAssKeepsEveryRoleOfAChorusLine` |
| A file name is truncated on a character boundary to `AppLimits.maxFileNameBytes` | `testLongRoleNameStillWrites` |
| DOCX stays valid XML with control characters in the text | `testDocxStaysValidXmlWithControlCharacters` |
| Both languages carry the same keys, the same plural keys and the same placeholders | `testBothLanguagesCarryTheSameKeys`, `testBothLanguagesCarryTheSamePluralKeys`, `testBothLanguagesUseTheSamePlaceholders` |
| A placeholder is substituted once, never into text another value inserted | `testFormatSubstitutesEachPlaceholderOnce` |
| SRT and VTT survive the round trip: escaping, an empty line inside a cue, a line with no role | `testSrtAndVttRoundTrip` |
| A queue run gives every file its own roles and colours | `testExportQueueUsesOwnRolesForEachFile` |
| The output folder is refused unless it exists, is a directory and is writable | `testOutputFolderRejectsUnusablePaths` |
| A failure mid-run reports the files already written | `testPartialExportKeepsFilesWrittenBeforeFailure` |
| An oversized file and a directory are refused before the parser runs | `testImportRejectsOversizedAndNonRegularFile` |
| SRP is decoded by its declared encoding, and a DOCTYPE is refused before the parser expands it | `testSrpInWindows1251KeepsRoles`, `testSrpRejectsDoctypeBeforeParsing` |
| A blank line carrying whitespace still separates two cues | `testSpacedBlankLineSplitsSrtBlocks` |
| ASS export keeps `Layer`, the margins and `Effect` of the source line | `testAssExportKeepsLayerMarginsAndEffect` |
| The assembled file name fits the file system limit, base and role together | `testLongBaseAndRoleFitFileNameLimit` |
| Thousands of lines export to every format in one run | `testLargeFileExportsEveryFormat` |

Known ceiling: `testEveryKeyUsedInCodeExists` finds keys with a regular expression, so keys held
in tables such as `[("qa.q1", "qa.a1")]` are invisible to it. The check is one-directional and
will not catch a missing translation for a key used that way.

## Maintaining this file

When a mistake happens, fix it at the strongest layer that can hold it, in this order: a test
that fails on the mistake, then a rule here, then a correction in conversation. A correction in
conversation dies with the session.

A remark made about the same thing three times stops being a remark. First time, a rule here.
Second time, check the rule is being read. Third time, it becomes a test and the rule is deleted
from this file.

Prune when a rule is covered by a test, when two rules contradict each other, or when a rule no
longer matches how the code works. Slow growth of this file is the sign it is working.
