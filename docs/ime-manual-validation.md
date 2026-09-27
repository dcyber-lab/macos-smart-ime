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

The first build downloads the rime-ice Chinese tables (about 28 MB, SHA-256 verified) into `build/rime-data/`; later builds reuse them. See `third_party/librime-data/smartime/NOTICE.md` for licensing.

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

### Development loop without sudo

On a development machine, run once:

```bash
sudo scripts/ime/enable-dev-install.sh
```

This makes `/Library/Input Methods/SmartIMEHost.app` owned by the developer account. After that, build, install, and run the TextEdit smoke test with no password prompt:

```bash
scripts/ime/dev-cycle.sh            # build + install --system + smoke test
scripts/ime/dev-cycle.sh --no-test  # build + install only
```

Trade-off: any process running as the developer account can modify the installed input method. A later `sudo scripts/ime/install-host.sh --system` restores `root:wheel` ownership and turns this mode off.

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
13. Type `yunyuansheng`, `neijuan`, and `fupan` and confirm 云原生, 内卷, and 复盘 are the first candidates (rime-ice vocabulary)

This milestone is not considered complete until steps 5 through 13 are verified in a real macOS text client with the visible candidate panel.

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

## English Candidates In Chinese Mode Checklist

Use a normal editable text field such as TextEdit, in Chinese mode.

1. Type `shujuku`
2. Confirm 数据库 is first and `database` appears after the Chinese candidates
3. Press the number key of `database` and confirm `database` is committed with no trailing space
4. Type `hello`
5. Confirm `hello` is the first candidate, then press `Space` and confirm `hello` is committed
6. Type `women`
7. Confirm 我们 is first, followed later by `we`, `us`, and `women`; press `Space` and confirm 我们 is committed
8. Type `gith`, confirm `github` appears after the Chinese candidates, press `Down` until it is highlighted, then press `Space` and confirm `github` is committed
9. Type `deploy`, press the number key of the first Chinese candidate (2), and confirm that Chinese candidate is committed
10. Type `nihao`, then press `=` (next page) and confirm the English candidates disappear on page 2
11. Type `hello` and press `Return`, and confirm the raw input `hello` is committed
12. Type `zg` and confirm no English candidates appear
13. Type `shujuk` (unfinished) and `sjk` (abbreviation) and confirm `database` appears after the Chinese candidates
14. Type `gith` and confirm `GitHub` is the second candidate; press `2` and confirm `GitHub` is committed
15. Type `dep` and confirm the first candidate is Chinese (得票), not an English word
16. Type `kube`, `json`, and `refac` and confirm `Kubernetes`, `JSON`, and `refactor` are offered
17. Type `depl` and confirm `deployed 部署` shows its gloss in small gray text, while the translation `database` for `shujuku` shows none
18. Switch to English mode, type `negot`, and confirm completions show glosses such as `negotiate 商议，谈判`

This milestone is not considered complete until steps 1 through 18 are verified in a real macOS text client.

## Automated Smoke Test

`scripts/ime/dev-cycle.sh` builds and installs the host, then runs the smoke test (`scripts/ime/build-e2e.sh` builds it from `scripts/ime/e2e/`):

- `SmartIMETestClient.app` is a throwaway window with one text view. It never opens documents or writes anywhere except a temporary state directory, so the test cannot touch the user's apps or files.
- `SmartIMEDriver` waits until the keyboard and mouse have been idle for 5 seconds, posts synthetic keys only to the test client, and checks the committed and marked text: Space, number keys, translation, Return, Escape, raw preedit for `good`, the Shift toggle, and a row click. It prints the live panel size.
- It aborts on a real key press or when the test window loses focus, restores the previous input source and app, and exits non-zero on any failure.

Run it after every change to the IME host before hand-off.

## Candidate Panel Checklist

Use a normal editable text field such as TextEdit.

1. In light appearance, type `shujuku` in Chinese mode
2. Confirm a rounded vertical panel appears just below the caret with the pinyin (`shu ju ku`) in small gray text at the top, numbered rows, 数据库 highlighted with a soft accent tint, a separator line above `database`, and a capsule 译 tag on `database`
3. Confirm a down chevron appears next to the pinyin; press `=` and confirm both up and down chevrons appear on page 2
4. Confirm the panel is exactly as tall as its rows, with no empty space below; type `huiyi` and confirm the panel resizes
5. Press `Down` twice and confirm the highlight moves to the third row
6. Click the `database` row and confirm `database` is committed and the panel disappears
7. Type `hello` and confirm `hello` is first with an 英 tag and a separator below it
8. Press `Shift` to switch to English mode, type `he`, and confirm the rows have no tags or separators
9. Switch the system to dark appearance and repeat step 1; confirm the panel background and text follow dark colors
10. Move the caret near the bottom and the right edge of the screen and confirm the panel flips above the caret and stays fully on screen
11. Type `nihao`, press `Escape`, and confirm the panel disappears and nothing is inserted; type again, switch to another app, and confirm the panel does not stay behind

This milestone is not considered complete until steps 1 through 11 are verified in a real macOS text client.

## Known Limits In This Milestone

- This checklist validates both the Chinese `librime` path and the basic English completion path
- English mode completes from a bundled 30,000-word frequency list generated from wordfreq (`scripts/english/build-wordlist.py`); there is no user dictionary or learning yet
- `Shift` key toggle is a simple heuristic based on standalone press/release
- Basic input (Space, number keys, Enter, Escape) was confirmed working in a real client on 2026-09-27 after the text-commit fix; the English mode and mixed-candidate checklists still need a full pass
- Switching the default schema from `luna_pinyin` to `smartime_pinyin` starts a new user dictionary; words learned under `luna_pinyin` do not carry over
- Install with `sudo scripts/ime/install-host.sh --system`. On the development machine, a user-level install alone (`~/Library/Input Methods`) was never launched by `imklaunchagent` (`LaunchInputMethod() Error, status=-50`); the root cause is not yet known
- Removing or replacing the IME bundle while its process runs can leave already-open apps holding a dead input method connection; relaunch those apps (or log out and back in) if typing passes through as plain letters
- Richer candidate controls and mixed-mode input are still follow-up milestones
- The app target is still using local-development settings, not a release distribution setup
- The validated registration shape for `SmartIMEHost` is a selectable `TISTypeKeyboardInputMethodWithoutModes` source rather than a mode-driven input method bundle.
