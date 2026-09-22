# Codex Process Cleaner

<p align="center">
  <img src="Resources/AppIcon.png" alt="Codex Process Cleaner app icon" width="160">
</p>

[English](README.md) | [简体中文](README.zh-CN.md)

A small native macOS utility that finds processes started by Codex project tasks and left running after their parent task has ended. It is not limited to specific executable names and does not treat unrelated development processes as Codex processes.

## Features

- Uses the inherited `CODEX_THREAD_ID` marker and follows descendants created by that process.
- Finds detached background programs even after macOS has re-parented them, including Vite, esbuild, local databases, and custom executables.
- Shows PID, memory, CPU, running time, command, and safety status.
- Marks detached processes as recommended when they have run for over one hour with low CPU usage.
- Supports selected shutdown and a confirmed “close all closeable processes” action.
- Protects the Codex app, current interface, and the cleaner itself.
- Sends `SIGTERM` only. It does not delete files and does not need administrator access.
- Native AppKit application with no third-party runtime or package dependency.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools when building from source

The release script creates a universal binary for Apple Silicon and Intel Macs.

## Build

```bash
git clone https://github.com/tortorse/codex-process-cleaner.git
cd codex-process-cleaner
./scripts/build-release.sh
```

Outputs:

- `build/CodexProcessCleaner.app`
- `dist/CodexProcessCleaner-macOS-universal.zip`

For a faster build for the current Mac only:

```bash
./scripts/build-app.sh
```

## Opening an unsigned build

Local and GitHub Actions builds use an ad-hoc signature. On first launch, macOS may refuse a normal double-click because the app has not been notarized by Apple. Right-click the app, choose **Open**, then confirm **Open**.

For normal double-click distribution without that warning, sign with an Apple Developer ID certificate and submit the app to Apple notarization.

## How “Close All” works

“Close All…” includes both recommended and manual-review rows, so active Codex tasks may stop. A warning shows the current process count and memory before anything is sent. Protected processes are always excluded.

Codex may restart helpers it still needs. The app refreshes after shutdown so the list shows what remains.

## Privacy

All inspection happens locally with macOS `ps`. The app extracts only the Codex task ID from process environments and does not display or save other environment variables. It has no network code and does not upload process information.

## License

[MIT](LICENSE)
