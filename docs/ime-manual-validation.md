# IME Manual Validation

This document is the repository-owned checklist for installing and manually validating the current `SmartIMEHost` milestone.

## Prerequisites

- Full Xcode is installed and active through `xcode-select`
- `xcodegen` is installed
- `librime` is installed through Homebrew: `brew install librime`
- The repository includes the bundled minimal Rime data under `third_party/librime-data/minimal`

## Build

Run:

```bash
scripts/ime/build-host.sh
```

Expected result:

- `build/ime-host/SmartIMEHost.app` exists

## Install

Install for the current user:

```bash
scripts/ime/install-host.sh
```

Expected result:

- `~/Library/Input Methods/SmartIMEHost.app` exists

For a system-wide install instead:

```bash
sudo scripts/ime/install-host.sh --system
```

To remove the install later:

```bash
scripts/ime/uninstall-host.sh
```

For a system-wide uninstall:

```bash
sudo scripts/ime/uninstall-host.sh --system
```

## Enable The Input Method In macOS

The exact labels can vary slightly by macOS version, but the flow should be:

1. Open `System Settings`
2. Go to `Keyboard`
3. Open the `Input Sources` or `Text Input` management UI
4. Add or enable `SmartIMEHost`
5. Use the menu bar input source switcher to select it

If the input source does not appear immediately:

- re-open the input source settings UI
- log out and log back in
- or remove and reinstall the app, then check again

## Basic Chinese Input Checklist

Use a normal editable text field such as TextEdit.

1. Switch to `SmartIMEHost`
2. Type a simple pinyin sequence such as `nihao`
3. Confirm a composition string appears
4. Confirm candidate items appear
5. Press `Space` or `Return` to commit the current candidate
6. Confirm Chinese text is inserted into the text field

## Known Limits In This Milestone

- This checklist validates the current Chinese `librime` path only
- Richer candidate controls are still a follow-up milestone
- The app target is still using local-development settings, not a release distribution setup
- In this session, the repository-owned scripts were verified through build and user-local installation. The remaining manual step is enabling the input source in macOS and confirming the live typing loop in a GUI text client.
