# IME Host Bootstrap

This directory contains the IME host milestones for the project.

## What Exists In This Milestone

- `App/AppDelegate.swift`
- `App/main.swift`
- `Resources/Info.plist`
- `Sources/IMEHostCore/IMEInputController.swift`
- `Sources/IMEHostCore/IMEHostSessionStore.swift`
- `Sources/IMEHostCore/IMEHostServer.swift`
- `Sources/IMEHostCore/IMEHostConfiguration.swift`

The current milestone proves the intended boundary:

- InputMethodKit host-side entrypoints live in `apps/ime`
- Session and candidate state are represented explicitly
- Chinese composition is delegated through `packages/rime-bridge`
- The first bridge milestone uses `third_party/librime-data/minimal` as local shared data

## Local Validation Assumptions

To validate the IME host as a real macOS input method, the machine needs:

- Full Xcode, not only Command Line Tools
- `librime` installed through Homebrew: `brew install librime`
- The generated `macos-smart-ime.xcodeproj`
- Bundle metadata and an installation flow for enabling the input method in macOS
- The repository install scripts under `scripts/ime`

## Generate The Xcode Project

```bash
xcodegen generate
```

## Build The IME Host App

```bash
scripts/ime/build-host.sh
```

The generated app is placed at:

```text
build/ime-host/SmartIMEHost.app
```

## Install For Manual Testing

For manual testing as an input method, run:

```bash
sudo scripts/ime/install-host.sh
```

To remove the installed app later, run:

```bash
sudo scripts/ime/uninstall-host.sh
```

For the full checklist, see [`docs/ime-manual-validation.md`](../../docs/ime-manual-validation.md).

## Current Validation Status

The repository now includes:

- A generated Xcode project
- A buildable `SmartIMEHost` macOS app target
- InputMethodKit bundle metadata and host wiring
- A project-owned `rime-bridge` package wired into the host
- Local `librime` shared data configured through the Xcode build settings
- A scripted install and uninstall workflow for manual validation

The next practical validation step is running the manual checklist in [`docs/ime-manual-validation.md`](../../docs/ime-manual-validation.md) after installation.
