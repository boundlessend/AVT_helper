# AVT_helper

[![CI](https://github.com/boundlessend/AVT_helper/actions/workflows/ci.yml/badge.svg)](https://github.com/boundlessend/AVT_helper/actions/workflows/ci.yml)
[![Release DMG](https://github.com/boundlessend/AVT_helper/actions/workflows/release.yml/badge.svg)](https://github.com/boundlessend/AVT_helper/actions/workflows/release.yml)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![License](https://img.shields.io/badge/License-MIT-green)

`AVT_helper` is a small native macOS utility for converting subtitle files and creating DOCX dialogue tables.

The app imports common subtitle formats, exports subtitles to other common formats, builds DOCX files with timings, roles, dialogue, and role statistics, and can create role-assignment DOCX files with Word highlight colors.

## Features

- Swift 5.9+, SwiftUI, AppKit, no external package dependencies.
- Import `ASS`, `SSA`, `SRT`, `VTT`, and `SRP`.
- Export `ASS`, `SRT`, and `VTT`.
- Export `DOCX` with file title, detected roles, timing/role/dialogue table, and role statistics.
- Drag and drop subtitle files into the input area.
- Role assignment by voice count, voice gender, role gender, and line count balancing.
- Word-compatible highlight colors for assigned roles.
- Russian interface by default, with English available in Settings.
- About, Q&A, and Settings windows.
- Optional post-processing actions: open output folder and close the app after processing.

## Requirements

- macOS 13 or newer.
- Xcode Command Line Tools or Xcode.

## Install

1. Open `AVT_helper.dmg`.
2. Drag `AVT_helper.app` to `Applications`.
3. Try to open the app from `Applications`.
4. If macOS blocks the app because it is unsigned, remove the quarantine attribute:

```bash
sudo xattr -rd com.apple.quarantine "/Applications/AVT_helper.app"
```

For a custom install path, replace `/Applications/AVT_helper.app` in the `xattr` command with the real `.app` path.

5. Open the app again.

## Usage

1. Open `AVT_helper.app`.
2. Click `Open subtitles` or drag a subtitle file into the input area.
3. Choose the output folder.
4. Select one or more export formats: `ASS`, `SRT`, `VTT`, or `DOCX`.
5. Click `Start`.
6. For role assignment, load a subtitle file with roles and click `Make role assignment`.

## DOCX Output

DOCX export creates:

- centered bold file name;
- list of all detected roles;
- table with `Timing`, `Role`, and `Dialogue` columns;
- centered timing and role columns;
- role statistics in the format `Role name - line count`.

Role-assignment DOCX uses the same layout and highlights assigned roles with the selected Word highlight colors.

## Build

Build the SwiftPM executable:

```bash
swift build
```

Build a `.app` bundle:

```bash
./scripts/build_app.sh
```

The app bundle is written to:

```text
.build/AVT_helper.app
```

Build a DMG:

```bash
./scripts/build_dmg.sh
```

The DMG is written to:

```text
.build/AVT_helper.dmg
```

Install and run the app locally:

```bash
./run_app.command
```
