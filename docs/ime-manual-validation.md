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
- the built bundle is ad-hoc signed
- the main executable is not a Debug `@rpath/...debug.dylib` wrapper

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

The system-wide install path should leave the bundle owned by `root:wheel`.

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
5. Confirm `SmartIMEHost` appears in the menu bar input source switcher
6. Confirm the normal input-source keyboard shortcut can cycle to `SmartIMEHost`
7. Use the menu bar input source switcher or the keyboard shortcut to select it

If the input source does not appear immediately:

- re-open the input source settings UI
- log out and log back in
- or remove and reinstall the app, then check again
- prefer keeping only one install location at a time; for the current validated setup, keep `/Library/Input Methods/SmartIMEHost.app` and remove any duplicate copy from `~/Library/Input Methods/`

## Basic Chinese Input Checklist

Use a normal editable text field such as TextEdit.

1. Confirm `SmartIMEHost` appears in `System Settings` as a selectable input source
2. Confirm `SmartIMEHost` appears in the menu bar input source switcher
3. Confirm the input-source keyboard shortcut can reach `SmartIMEHost`
4. Switch to `SmartIMEHost`
5. Type a simple pinyin sequence such as `nihao`
6. Confirm a composition string appears
7. Confirm candidate items appear in simplified Chinese by default
8. Press `Space` and confirm the first candidate commits
9. Press `Down Arrow` and `Up Arrow` to confirm the visible candidate highlight moves with the current selection
10. Type a candidate sequence again and press `1` to confirm the first visible candidate can be chosen by number key
11. Type another candidate sequence and press `Escape` to confirm the composition is cleared without committing text
12. Confirm Chinese text is inserted only for the committed cases

This milestone is not considered complete until steps 5 through 11 are verified in a real macOS text client with the visible candidate panel.

## Basic English Mode Checklist

Use a normal editable text field such as TextEdit.

1. Switch to `SmartIMEHost` (it starts in Chinese mode by default)
2. Press and release the `Shift` key
3. Confirm the system toggles to English mode (check logs or try typing)
4. Type `he`
5. Confirm an English composition string `he` appears
6. Confirm the candidate window shows `he` first, followed by frequency-ranked completions (e.g., "her", "here", "help")
7. Press `Space`
8. Confirm the typed text `he` is committed followed by a space (Space never swaps the typed word for a completion)
9. Type `th` and press `2`
10. Confirm the second candidate ("the") is committed
11. Type `deplo`, press `Down` until "deployment" is highlighted, then press `Space`
12. Confirm "deployment " is committed
13. Press and release `Shift` again to toggle back to Chinese mode
14. Confirm typing `nihao` now produces Chinese candidates again

This milestone is not considered complete until steps 1 through 14 are verified in a real macOS text client.

## Known Limits In This Milestone

- This checklist validates both the Chinese `librime` path and the basic English completion path
- English mode completes from a bundled 30,000-word frequency list generated from wordfreq (`scripts/english/build-wordlist.py`); there is no user dictionary or learning yet
- `Shift` key toggle is a simple heuristic based on standalone press/release
- This session rebuilt the host after adding English mode and `IMKCandidates` sync, but did not re-run a full GUI validation pass for the new interactions
- Richer candidate controls and mixed-mode input are still follow-up milestones
- The app target is still using local-development settings, not a release distribution setup
- The validated registration shape for `SmartIMEHost` is a selectable `TISTypeKeyboardInputMethodWithoutModes` source rather than a mode-driven input method bundle.
