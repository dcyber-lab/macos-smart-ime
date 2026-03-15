# IME Host Bootstrap

This directory contains the first IME host shell milestone for the project.

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
- The host can support a deterministic commit path without `librime`

## Deterministic Validation Behavior

- Typing the trigger `test`
- Then committing the composition
- Should produce the committed text `IME shell ready`

This is a host-shell validation behavior, not final product logic.

## Local Validation Assumptions

To validate the IME host as a real macOS input method, the machine needs:

- Full Xcode, not only Command Line Tools
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

The next practical validation step is installing the built app into `/Library/Input Methods/` and confirming it appears as an input source in macOS.
