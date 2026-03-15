# Implementation Log

## 2026-03-15

### Bootstrap

- Created the local project workspace.
- Added project-level instructions in `AGENTS.md`.
- Added local brief and technical design documents.
- Linked the local workspace to the Notion project page, design document, and task database.
- Initialized the local Git repository on `main`.
- Added project Git workflow rules and agent entry files.
- Created the GitHub repository and pushed `main` to `origin`.
- Installed OpenSpec in the repository and enabled multi-agent workflow files.
- Added a project rule that new features must go through OpenSpec before implementation.
- Created the first OpenSpec change, `init-ime-shell`, for the IME host bootstrap milestone.
- Added initial IME host shell source files, shared session models, and bootstrap documentation.
- Configured the machine to use the full Xcode toolchain and accepted the Xcode license.
- Verified `swift build` now succeeds for the current Swift package targets after fixing the optional `IMKServer` return type in `IMEHostServer`.
- Added a generated Xcode project and a real `SmartIMEHost` macOS app target wired to InputMethodKit.
- Verified `xcodebuild -project macos-smart-ime.xcodeproj -scheme SmartIMEHost -configuration Debug build` succeeds.
- Added the `add-rime-bridge` OpenSpec change and completed its planning artifacts before implementation.
- Installed local Homebrew `librime` and added the first `packages/rime-bridge` wrapper around the minimum runtime and session APIs.
- Replaced placeholder Chinese composition handling in `IMEHostCore` with bridge-backed updates and commit routing.
- Documented the local `librime` data dependency used by the first bridge milestone.
- Moved the minimal runtime Rime data into `third_party/librime-data/minimal` so the repository no longer depends on an untracked `third_party/librime-src` checkout.
- Added repository-owned IME build/install/uninstall scripts and a manual validation checklist for the current Chinese input path.
- Verified `scripts/ime/build-host.sh` produces `build/ime-host/SmartIMEHost.app` and `scripts/ime/install-host.sh` installs the app into `~/Library/Input Methods/SmartIMEHost.app`.
- The remaining manual validation step is enabling `SmartIMEHost` in System Settings and checking live Chinese input in a GUI text client.
- Updated the IME app bundle metadata to register as a visible macOS input source by adding `ComponentInputModeDict`, `TISIntendedLanguage`, and `LSUIElement`, and by removing the older background-only app configuration.
- Rebuilt and reinstalled `SmartIMEHost`, then refreshed `TextInputMenuAgent` and `System Settings` so macOS can rescan the updated input source metadata.
- Confirmed through `TISCreateInputSourceList` that macOS still was not recognizing the earlier bundle as a text input source.
- Identified the deeper packaging issue: the previous build/install flow was copying a Debug-style app whose executable depended on `@rpath/SmartIMEHost.debug.dylib` and whose bundle resources were not properly sealed for installation.
- Updated the build/install workflow to produce a Release-style bundle, ad-hoc sign it, and normalize ownership for system-wide installs.
- Added a bundle icon and `tsInputMethodIconFileKey`, and changed the registration shape from a mode-based input method to a selectable `TISTypeKeyboardInputMethodWithoutModes` input source, which matched the working third-party reference input method on this machine.
- Verified the final registered source is `lab.dcyber.inputmethod.smartime` with `ENABLED=1` and `SELECTABLE=1`, then removed the duplicate user-level install so only `/Library/Input Methods/SmartIMEHost.app` remains.
- Started the next OpenSpec change, `add-basic-chinese-candidate-interactions`, and added the first host-side cancel behavior so `Escape` clears active Chinese composition cleanly.
- Fixed the IME host event-return contract after review: `Escape` is now handled before sending the event to `librime`, and the host returns `true` whenever a composition update or commit is produced so raw keystrokes do not leak through to the client.
- Added the `fix-ime-switcher-visibility` OpenSpec change after finding that `SmartIMEHost` could register in System Settings while still failing to appear in the menu bar switcher and keyboard-cycle path.
- Tightened the IME bundle display metadata with `CFBundleDisplayName`, localized `InfoPlist.strings`, and explicit `tsInputMethodLanguageKey` so the installed bundle more closely matches a working third-party input method's UI-facing shape.
- Extended the install workflow to repair malformed `AppleEnabledInputSources` keyboard-input-method entries for the logged-in user, de-duplicate the `SmartIMEHost` entry, and re-enable the source after registration.
- Expanded the manual validation checklist so switcher visibility and keyboard-cycle visibility are validated separately from System Settings visibility.
- Identified the root cause of the menu bar switcher visibility issue: the install script was replacing the app bundle on disk while a stale SmartIMEHost process was still running, leaving a zombie process with a broken IMKServer connection. The system could detect the input source but could not communicate with it, causing selection attempts to fail silently and fall back to another input method.
- Fixed the install script to kill any running SmartIMEHost process before replacing the bundle, wait for clean exit, and also restart `TextInputSwitcher` alongside `TextInputMenuAgent` and `SystemUIServer`.
- Added a post-install verification step that confirms SmartIMEHost is enabled and selectable via the TIS API.
- Added resilience to `AppDelegate`: if `IMKServer` fails to start (returns nil), the process now exits after 1 second so the system can relaunch it cleanly instead of leaving a zombie.
- Removed the redundant `InputMethodServerDelegateClass` from Info.plist (the controller class is sufficient).
- Verified all 4 enabled keyboard input sources (ABC, Pinyin, hallelujah, SmartIMEHost) can be selected and round-tripped via `TISSelectInputSource` without fallback.
- User confirmed the switcher-visibility issue is now resolved and no blocking issue remains for this milestone.
- This session did not rerun `sudo scripts/ime/install-host.sh --system` because the command requires an interactive sudo password.
- Created the `complete-chinese-input-loop` OpenSpec change to close the remaining gap between registered input-source visibility and a real Chinese typing loop.
- Updated `IMEInputController` to keep inline composition and an explicit `IMKCandidates` panel in sync, hide candidate UI on commit/cancel/deactivation, and commit candidate-panel selections back into the focused client.
- Rebuilt `SmartIMEHost` successfully after the candidate-loop changes; importing `InputMethodKit` with `@preconcurrency` was required so the legacy IMK candidate APIs would compile cleanly under Swift 6.
- The remaining milestone gap is now explicit: this repository state still needs a real GUI validation pass in TextEdit or another normal macOS text client to confirm `nihao` shows visible candidates and that `Space`, number-key selection, and `Escape` all behave correctly end to end.

### Expected Usage

- Add a new dated section for each meaningful coding session.
- Record architecture changes, interface changes, and follow-up work.
- Keep this file short and factual.
