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

## Generate The Xcode Project

```bash
xcodegen generate
```

## Build The IME Host App

```bash
xcodebuild -project macos-smart-ime.xcodeproj -scheme SmartIMEHost -configuration Debug build
```

The generated app is placed under Xcode DerivedData, for example:

```text
~/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug/SmartIMEHost.app
```

## Install For Manual Testing

For manual testing as an input method, copy the built app into:

```text
/Library/Input Methods/
```

After copying, re-log in or refresh input sources in macOS before trying to enable it.

## Current Validation Status

The repository now includes:

- A generated Xcode project
- A buildable `SmartIMEHost` macOS app target
- InputMethodKit bundle metadata and host wiring
- A project-owned `rime-bridge` package wired into the host
- Local `librime` shared data configured through the Xcode build settings

The next practical validation step is installing the built app into `/Library/Input Methods/` and confirming it appears as an input source in macOS.
