# IME Host Bootstrap

This directory contains the first IME host shell milestone for the project.

## What Exists In This Milestone

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
- A macOS InputMethodKit app target or bundle target
- Bundle metadata and installation flow for enabling the input method in macOS

## Current Environment Blocker

This repository currently has source and package wiring for the host shell, but this machine cannot complete full IME app validation yet because:

- `xcodebuild` is unavailable with the active developer directory
- The current command line toolchain and SDK do not provide a clean local build path for this target

The next environment step is to point `xcode-select` at a full Xcode installation and add the actual app target/bundle packaging layer.
