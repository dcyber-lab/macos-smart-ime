# Implementation Log

## 2026-09-30

### English candidates learn from the user's picks

- Implemented OpenSpec change `learn-candidate-choices`. New `UserData` target (`packages/user-data`) with `CandidateHistory`; `EnglishAugmentedChineseEngine` and `BasicEnglishEngine` rank with it and record commits; the host shares one instance per process.
- Chinese ranking was already learning: probing the bundled librime with a copy of the user's real `smartime_pinyin.userdb` moved `he` → 合, `shi` → 时, `gj` → 根据, `sj` → 数据 to first place versus an empty user directory. Left unchanged.
- Verified against real librime and the bundled data (scratch user directory): `gith` → GitHub moves from 2 to 1 after one pick; `shujuku` → database moves from 6 to 2 after one pick and to 1 after two more; picking Chinese for `hello` puts Chinese first; English-mode `dep` → deployment moves from 4 to 2. The stored file holds no Chinese text.
- Cost with 5,000 learned words all matching the typed prefix: mean keystroke 0.37 ms versus 0.23 ms without history (librime included; engines built unoptimized).
- This machine has only the Command Line Tools (no XCTest, and SwiftPM fails to load), so the 81 `EnglishEngineTests` and `UserDataTests` cases ran through `swiftc` with a local XCTest stand-in, and `IMEHostCore` was compiled against the bundled librime. `swift test`, the app build, and the smoke test run in CI (`package.sh`); the learning checklist in `docs/ime-manual-validation.md` still needs a pass in a real client.

## 2026-09-27

### CI build

- Added `.github/workflows/build.yml`: on `macos-26`, installs `librime`, `xcodegen`, and `pkgconf`, caches the rime-ice download, and runs `scripts/release/package.sh`, the script used for local release builds. Pull requests to `main` upload the zip (kept 7 days); `v*` tags publish the release after checking the tag against `MARKETING_VERSION`. Documentation-only pull requests are skipped to save macOS minutes (10x against the 2,000 free minutes of a private repository).
- `package.sh` now runs `swift test` first, so a local run checks the same things as CI. `install.sh` also installs `pkgconf`, which SwiftPM uses to find librime.
- The smoke test stays local (`./install.sh --test`): it needs Accessibility access to post keystrokes.

### Release package

- Added `scripts/release/package.sh`, which produces `build/release.noindex/LinguaType-<version>-macOS-arm64.zip` (27 MB): the app with librime and its Homebrew dependencies (glog, gflags, yaml-cpp, leveldb, snappy, marisa, opencc) in `Contents/Frameworks` under `@rpath`, ad-hoc signed, plus `install-host.sh`, `install.command`, `README.txt`, and the third-party licenses. `--publish` uploads it as a GitHub release.
- The Homebrew bottles are arm64-only with `minos 26.0`, so the package sets `LSMinimumSystemVersion` to 26.0. Older macOS or Intel Macs would need librime built from source.
- Rime data now ships in the app (`Contents/Resources/RimeData`) with tables precompiled at build time (compiling takes about 2 s; a fresh user directory then deploys without compiling). The `RimeSharedDataDirectory` Info.plist key, which pointed into the developer's checkout, is gone, and `install-host.sh` no longer runs `rime_deployer`.
- Input source registration moved from three `swift -e` snippets in `install-host.sh` into the app (`SmartIMEHost --install`), so installing needs no Swift toolchain. `install-host.sh` takes an optional app path and clears the quarantine attribute.
- `build-host.sh` unregisters the DerivedData product that `xcodebuild` registers with LaunchServices.
- Verified: the probe loaded only bundled libraries and returned 你好; the packaged app installed with `install-host.sh` passed the smoke test 15/15, and the running input method mapped `librime.1.dylib` from `Contents/Frameworks`. Not yet verified: the first-time `sudo` path of `install.command` on a Mac without Homebrew or Xcode.

### One-step install and update

- Added `./install.sh`: checks Xcode and Homebrew, installs `librime` and `xcodegen` when missing, builds, and installs into `/Library/Input Methods`. The first install runs `install-host.sh` and `enable-dev-install.sh` under sudo (one password prompt), later runs update without sudo. `--pull` fast-forwards the checkout first; `--test` runs the smoke test. It replaces `scripts/ime/dev-cycle.sh`.
- Build output moved to `build/ime-host/Products.noindex` and `DerivedData.noindex`. Spotlight indexes app bundles in ordinary folders and registers them with LaunchServices within about 5 seconds (a probe copy in a plain folder was registered after 5 s, one in a `.noindex` folder not within 60 s). That happened after `install-host.sh` had unregistered the build copy, and `imklaunchagent` then failed to launch LinguaType (`LaunchInputMethod() Error, status=-50`). `build-host.sh` removes and unregisters output left at the old paths.
- `install-host.sh` now stops the previous instance only after the new bundle is in place.
- Restarting `imklaunchagent` (`killall`, done once while debugging at 15:27) left it degraded until the next login: the login agent relaunched LinguaType 1–3 seconds after every restart between 13:03 and 15:05, while restarted agents kept serving the dead endpoint for about 40 seconds after the input method exited and failed with `-50` when asked within seconds of starting. The scripts never restart it; a logout and login restores it.

### Repository cleanup

- Removed the OpenSpec commands and skills that `openspec init` generated for 24 AI tools other than Claude Code, plus `GEMINI.md`; `.claude` keeps the OpenSpec workflow.
- Removed the OpenSpec change designs under `openspec/changes/`; git history keeps them.
- Removed unused code: `IMEInputController.activeEngine`, `CandidateSource.placeholder` / `.englishCorrection`, `InputMode.mixed`, and `Candidate.score` (set by every engine, never read).
- Dropped `third_party/librime-data/minimal` (luna_pinyin, cangjie5, essay, symbols). `smartime_pinyin` uses none of it, and luna_pinyin was a fallback schema the input method never selects; `default.yaml` now lists only `smartime_pinyin`, so installs compile one schema.
- 112 unit tests pass; smoke test 15/15. The first smoke test right after install failed because `imklaunchagent` relaunched the input method only 45 seconds after the install stopped it; rerun against the running input method, it passed.

### Larger English completion lexicon

- The previous hand-written `wordlist.txt` had 720 lines (not the 1000+ noted on 2026-03-20), including 71 duplicates, and was not frequency-ordered, so most prefixes produced few or no completions.
- Replaced it with the 30,000 most frequent lowercase English words from wordfreq 3.1.1, generated by `scripts/english/build-wordlist.py`. The generator drops profanity and slurs so they are never suggested. The data file is CC-BY-SA 4.0; attribution lives in `packages/english-engine/DATA_LICENSE.md`.
- Added `EnglishLexicon`, which loads the list once per process and serves frequency-ranked prefix lookups by binary search, instead of every `BasicEnglishEngine` reloading the file and scanning it linearly per keystroke.
- Candidate behavior: the typed text is always candidate 1 and completions follow by frequency; the panel hides when nothing completes. `Space` commits the highlighted candidate, or the typed text when nothing is highlighted. Without this, the larger lexicon made `Space` replace finished words with more frequent completions (`cat` became `catch`).
- Added the `EnglishEngineTests` SwiftPM test target (9 tests passing via `swift test`).
- Follow-up: the Xcode app build was not re-run because `xcodebuild` fails to load its plug-ins on this machine until `xcodebuild -runFirstLaunch` is run; the English checklist in `docs/ime-manual-validation.md` still needs a GUI pass.
- Follow-up: English candidates inside Chinese mode are being defined in a separate OpenSpec change.

### LinguaType branding

- Implemented OpenSpec change `rebrand-as-linguatype`. The input method is shown as "LinguaType" (灵译输入法 on Chinese systems) through localized `CFBundleDisplayName` / `CFBundleName`; the Rime schema is named 灵译拼音. Bundle, executable, bundle identifier, defaults domain, and scripts keep `SmartIMEHost`, so the installed input source did not need to be re-added.
- `scripts/branding/make-icons.swift` generates a template menu icon (`LinguaType.tiff`, rounded square with "中" and "A" cut out from real glyph outlines, `TISIconIsTemplate`) and a gradient app icon (`LinguaType.icns`) that replaces the green checkmark placeholder.
- PDF versions of the menu icon showed up as a solid white square in the input menu; system template icons (such as `Ainu.tiff`) are bitmap TIFFs, so the icon is a 16 px + 32 px TIFF.
- Removed the stale user-level copy in `~/Library/Input Methods` (an unused 12:11 build still registered as "SmartIMEHost" with the old icon); only the system-level LinguaType source remains, enabled and selectable.
- Build copies registered with LaunchServices under the same bundle ID made `imklaunchagent` fail to launch LinguaType; `install-host.sh` now unregisters them after installing. Apps that tried to switch to it while it was broken need a relaunch.
- The localized `CFBundleName` also renamed the running process in window lists, so the smoke test's `kCGWindowOwnerName == "SmartIMEHost"` check stopped finding the candidate panel; it now matches windows by the input method's process id. Smoke test 15/15 after the change.

### Selection translation promoted to a feature

- Implemented OpenSpec change `productize-selection-translation`. The direction is detected from the selection (Simplified Chinese → English when Han characters ≥ English words, otherwise English → Simplified Chinese; a 2× weighting was tried first and misrouted "这个feature要deploy到production"). The popup shows 中 → 英 or 英 → 中, and the missing-model message names the pair.
- Settings in the `lab.dcyber.inputmethod.smartime` defaults domain, read on every key: `SelectionTranslationEnabled` and `SelectionTranslationHotkey` (`ctrl+option+t` by default; invalid or modifier-less values fall back).
- `docs/technical-design.md` now allows explicit, user-triggered, asynchronous, on-device actions in the IME while keeping per-keystroke work free of AI, network calls, and long-running tasks.
- Smoke test 15/15, including real replacements in both directions ("你好meetinghellowomen测试he 数据库GitHub" → "Hello meeting hello women test he database GitHub"; "please review the plan" → 请查看计划). 112 `swift test` cases pass.

### Selection translation POC

- Implemented OpenSpec change `add-selection-translation-poc` inside the IME at the user's request (the documented home is the Companion app): select English, press `⌃⌥T`, read the on-device Chinese translation in a popup, `Return` replaces the selection, `Escape` dismisses. Uses Apple's Translation framework (`TranslationSession(installedSource:target:)`, macOS 26, weak-linked so the host still loads on older systems).
- `SelectionTranslationController` (7 tests with a fake translator: replace, escape, other keys, stale results, missing selection, missing model) drives `TranslationPopup`, a wrapping popup styled like the candidate panel.
- Smoke test now selects all text in the test client, checks that `⌃⌥T` opens the popup and `Escape` keeps the text (12/12 pass). Its model check first deadlocked by blocking the main thread on a semaphore while `LanguageAvailability` replied on the main actor; it now spins the run loop instead. After the user downloaded the English and Simplified Chinese translation languages, the full smoke test passes 14/14, including a real replacement ("please review the plan" → 请查看计划). The first attempt selected the test client's mostly Chinese text, which the framework returns unchanged, so the test now clears the client and types a pure English sentence in English mode before translating. Direct framework calls take about 100–200 ms per sentence.
- 100 `swift test` cases pass.

### Chinese glosses for English candidates

- Implemented OpenSpec change `add-english-candidate-glosses`. English word candidates in both modes show a short Chinese gloss after the word (`deployed 部署`, `Kubernetes 容器编排`, `negotiate 商议，谈判`); translation candidates show none. `Candidate` gained an optional `annotation`, drawn by the panel in 12 pt secondary text and truncated to 12 characters.
- `en-zh.tsv` (64,145 entries) is generated by `scripts/english/build-glosses.py` from ECDICT (MIT, pinned commit `bc015ed2`, SHA-256 verified). ECDICT's first sense is often not the common one and its `pos` share field is empty for all top-30k words, so the generator picks the part-of-speech line with the most senses, prefers function-word roles, keeps at most two short senses, uses only exact lowercase entries (so "gets" does not become the acronym GETS), borrows a lemma's gloss for inflection notes, falls back to `[计]` computing senses, and skips the 2,000 most common words.
- `supplement.txt` became `display<TAB>gloss` with hand-written workplace glosses (202 entries, now including deploy, review, ticket, download, password); they override ECDICT and extend to regular inflections of word-like terms (`deploying` → 部署), but not to acronyms (`AI` + `d` must not gloss "aid").
- Release benchmark: the glossary adds about 20 ms to the one-time load; per-keystroke latency is unchanged (p50 ≈ 0.05 ms, max ≈ 1.4 ms). Smoke test 10/10; 93 `swift test` cases pass.

### rime-ice Chinese dictionary

- Implemented OpenSpec change `adopt-rime-ice-dictionary`. The default schema is now `smartime_pinyin`, whose dictionary imports rime-ice's `8105`, `base`, `ext`, and `others` tables (about 890,000 entries); `luna_pinyin` remains as a fallback schema.
- The tables (GPL-3.0, 28 MB) are fetched at build time from pinned commit `3aea6d3694` with SHA-256 checks, cached under `build/rime-data/`, and assembled into `build/rime-data/shared`; they are not committed. Verified that a corrupted cache file is re-downloaded and that a checksum mismatch fails the build.
- `install-host.sh` precompiles the tables with `rime_deployer --build` (about 4 s; `smartime_pinyin.table.bin` is 28 MB). In the deploy run the table was written at 13:10:15 and the host started at 13:10:16, so the first keystroke did not wait for a Rime deploy.
- Real-librime comparison: 云原生, 内卷, 复盘 now come first (`luna_pinyin` gave 晕原声, 内眷, 覆盘). The smoke test passes 10/10 on the new dictionary.
- Known: words learned under `luna_pinyin` do not carry over; the first build needs network access.

### English candidates while typing and a larger lexicon

- Implemented OpenSpec change `improve-mixed-english-candidates`. Translations of the first Chinese candidate now appear for unfinished or abbreviated pinyin (`shujuk`, `sjk`, `huiy` → database / meeting), and for 4+ letter non-pinyin input the best common English completion is promoted to position 2 (`gith` → 1.个 2.GitHub; `Space` still commits Chinese).
- The word list grew from 30,000 to 100,000 wordfreq words. The profanity filter now also drops compounds by stem (with an allowlist for names such as Yamashita and words such as snigger). A project-authored `supplement.txt` (182 terms) adds technical and office vocabulary with display casing (GitHub, iOS, Kubernetes, JSON, TypeScript, OKR); common words that collide with brand names (Teams, Excel, Swift, Mr) were left out.
- The long tail collided with pinyin (`dep` became an exact English word, `shuj` offered romanized names), so Chinese mode only uses common words (rank < 30,000) plus the supplement, allowing rarer words only for 5+ letter non-pinyin input.
- Verified with real librime (`kube` → Kubernetes at position 2, `json` → JSON first, `dep` keeps 得票 first) and with the smoke test, which gained a `gith` + 2 → `GitHub` check: 10/10 pass. 85 `swift test` cases pass.

### Smoke test moved off TextEdit

- Incident: the TextEdit-based smoke test assumed its new document was the front one and read or closed "the front document". While the user was using TextEdit, their typing landed in the test document, cleanup closed their saved document, and every run had also left an autosaved `Untitled N.rtf` in the user's iCloud TextEdit folder. The leftover files (Untitled 2–7) were moved to the Trash with the user's approval.
- Replaced `scripts/ime/e2e-textedit.swift` with `scripts/ime/e2e/`: a throwaway `SmartIMETestClient.app` (one text view, publishes committed and marked text to a temporary directory) and a `SmartIMEDriver` that waits for 5 idle seconds, posts keys only to the client from a private event source, aborts on real key presses or focus loss, and adds a marked-text check for `good`. Built by `scripts/ime/build-e2e.sh`, run by `dev-cycle.sh`. Result: 9/9 pass.
- Not yet exercised: the abort paths (real key press, focus loss) have not been triggered in a real run.

### Raw input as preedit for non-pinyin input

- librime segments non-pinyin input into syllable fragments, so typing `good` in Chinese mode showed "go o d" inline and in the panel header. `EnglishAugmentedChineseEngine` now shows the raw input as the composition text when the input is all lowercase letters, cannot be segmented into pinyin, and has no converted Chinese part yet. Pinyin keeps librime's segmentation ("shu ju ku").
- Verified against real librime: `good` → "good", `github` → "github", `zg` → "zg", `shujuku` → "shu ju ku". 3 new tests; 72 `swift test` cases pass.

### Candidate panel visual refinements

- Softer highlight (accent tint with accent text instead of a solid accent fill; text lightened in dark mode for contrast), capsule 英/译 tags, and a Chinese-mode header showing the Rime preedit with up/down chevrons when more pages exist. `CompositionState` gained `isLastCandidatePage`, filled from `RimeMenu.is_last_page`.
- The user reviewed before/after renders in light and dark before deployment. `scripts/ime/dev-cycle.sh` then passed 8/8 in TextEdit; Chinese panels grew by the 21 pt header (e.g. `nihao` 107×211 pt), English mode is unchanged (85×233 pt). 69 `swift test` cases pass.

### Deploy and smoke test without sudo

- Every deploy needed the user to type a sudo password because the system-level bundle is `root:wheel`, and a user-level install alone is not launched on this machine.
- Added `scripts/ime/enable-dev-install.sh` (one-time sudo) to make the installed bundle owned by the developer account, and taught `install-host.sh --system` to update it without sudo when writable (it still fails fast with instructions otherwise). Rejected a passwordless sudoers rule because the script lives in a user-writable repository.
- Added `scripts/ime/dev-cycle.sh` (build, install, smoke test). The smoke test now posts a notification and waits 3 seconds before taking over the keyboard, and exits non-zero on any failed check.

### Candidate panel hugs its content

- The panel still looked fixed-size: a 150 pt minimum width made almost every Chinese list the same width with empty space on the right. Removed the minimum so the width follows the longest row, and tightened paddings (row height 26 pt instead of 28 pt). Added `testShortListsHugTheirContentWidth`; 61 `swift test` cases pass.

### Candidate panel wired and verified in TextEdit

- Re-wired the host-drawn `CandidatePanel` (OpenSpec `add-custom-candidate-panel`), replacing the fixed-height `IMKCandidates` panel that left empty rows under short lists. The panel height now fits its rows (3 new `CandidateListViewTests`; 60 `swift test` cases pass).
- Fixed Escape inserting the pinyin: `composedString` returned nil for an empty composition, so `updateComposition()` never cleared the client's marked text and the client later committed it. It now returns an empty string.
- Added `scripts/ime/e2e-textedit.swift`, which drives a fresh TextEdit document with synthetic events. Result on this build: 8/8 checks pass (Space → 你好, number key → translation "meeting", `hello` + Space, `women` + Return, Escape cancels, number key on a Chinese candidate, Shift → English `he` + Space, click on row 1 → 数据库). Measured live panel heights: 181 pt (6 rows), 208 pt (7 rows), 253 pt (9 rows).
- Deployment findings: a user-level install alone was never launched by `imklaunchagent` (`status=-50`), so the system-level install stays required. Deleting the system bundle while it ran, plus restarting `imklaunchagent`, left open apps with invalid IMK endpoints until they were relaunched.
- Pending: visual review of the live panel by the user (no screen-capture permission for automated screenshots).

### Text commit and Shift toggle fixes

- Root cause of "Space or a number key clears the composition but inserts nothing": `IMEInputController.commit` cast the client to `NSTextInputClient`. InputMethodKit's client proxies (`_IPMDServerClientWrapperModern`, `_IMKXPCCompatibilityDOProxyInterposerModern`, and the legacy variants) conform only to `IMKTextInput` (checked with the Objective-C runtime), so the cast always failed and committed text was dropped since the first Chinese input loop. `commit` now inserts through `IMKTextInput`, as Squirrel does.
- The `Shift` mode toggle fired on any Shift release, including Shift+letter and Cmd+Shift shortcuts, which silently switched to English mode. `ShiftToggleDetector` now toggles only on a standalone Shift tap; covered by 7 tests in the new `IMEHostCoreTests` target.
- While diagnosing, the host-drawn candidate panel from `add-custom-candidate-panel` was unwired; the host keeps using `IMKCandidates` until the panel is verified in a real client.
- Verified: the user confirmed basic input works in a real client after this build was deployed.
- Lesson: earlier changes were only unit-tested; any change to the IMK host layer must be checked end to end in a real app before hand-off.

### English candidates in Chinese mode

- Implemented OpenSpec change `add-english-candidates-in-chinese-mode`. `EnglishAugmentedChineseEngine` wraps `RimeBridgeEngine` and merges two kinds of English candidates into the Chinese list: English words from `EnglishLexicon` (`hello`, `deploy`, `gith` → github) and up to two translations of the first Chinese candidate from a new CC-CEDICT-based `ChineseEnglishDictionary` (`shujuku` → 数据库 … database).
- Placement: an exact English word goes first only when the input is not valid pinyin (`PinyinSyllableSegmenter`); otherwise English follows the Rime page (translations, then words). At most nine entries, deduplicated, first page only, inputs of three or more `[a-z]` letters.
- `CompositionState` gained `candidatePageIndex` (from `RimeMenu.page_no`) and `CandidateSource` gained `englishTranslation`.
- `zh-en.tsv` has 88,595 entries (2.3 MB) generated by `scripts/english/build-translations.py` from CC-CEDICT 2026-09-26. Release-build load time is ~55 ms once per process (the word list takes ~11 ms).
- Tests: 38 `swift test` cases pass, including 23 decorator scenarios against a fake engine. A probe against real `librime` with the repository's minimal data produced the expected lists (e.g. `huiyi` → 会议 … meeting, conference; `women` → 我们 … we, us, women).
- Known gaps: glosses follow CC-CEDICT order (部署 → dispose before deploy, 密码 → cipher), pinyin abbreviations are not translated, and there is no user translation table yet. The GUI checklist still needs a manual pass.

### Install script enable step

- `scripts/ime/install-host.sh` crashed with "Unexpectedly found nil" when the input source was installed but not yet enabled: the enable snippet called `TISCreateInputSourceList(filter, false)`, which only returns enabled sources. It now looks up all installed sources before calling `TISEnableInputSource`, and the verification snippet reports a missing source instead of crashing.
- After running `xcodebuild -runFirstLaunch`, `scripts/ime/build-host.sh` built the host and both `~/Library/Input Methods` and `sudo ... --system` installs were refreshed. TIS reports the source as enabled and selectable.
- Note: this machine has both a user and a system install with the same bundle ID. A stale system copy shadowed the user install until it was reinstalled; keep both in sync or uninstall one.

## 2026-03-20

### Space / Return not confirming candidates

- Root cause: Under InputMethodKit, `NSEvent` for Space (keyCode 49) can arrive with empty `characters` / `charactersIgnoringModifiers`. `RimeKeyTranslator` then returned `nil`, so `process_key` was never called; `handle(_:client:)` still returned `true` because `lastKnownState` still had composition text, so the key was swallowed and Rime never saw Space (first candidate / confirm).
- Fix: Map virtual key 49 explicitly to X11 keysym `0x20` (`XK_space`) in `RimeKeyTranslator.specialKeycode` so Space always reaches `librime`. Return was already mapped via keyCodes 36 and 76.

### Basic English Mode and Completion

- Added `EnglishInputEngine` protocol to `SharedModels`.
- Implemented `BasicEnglishEngine` in `packages/english-engine` with word buffering and prefix-based completion.
- Added a 1000+ word dictionary resource to `EnglishEngine` for completions.
- Updated `IMEInputController` to support `Shift` key toggling between Chinese and English modes.
- Extended `IMEInputController` event routing to use the active engine based on the current mode.
- Integrated English completion candidates into the `IMKCandidates` panel.
- Verified that `SmartIMEHost` builds successfully with the new English engine and mode-switching logic.
- Updated the manual validation checklist to include end-to-end English mode verification steps.

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
- Updated the Rime session bootstrap to force simplified Chinese output by default for the bundled `luna_pinyin` schema instead of the schema's traditional-first default presentation.
- Added explicit host-side candidate navigation and selection wiring so `Up Arrow`, `Down Arrow`, and number keys drive the current `librime` candidate selection state and keep the visible `IMKCandidates` highlight in sync.
- Rebuilt `SmartIMEHost` successfully after the simplified-output and candidate-selection fixes; GUI validation is still required to confirm the fixes behave correctly in a real macOS text client.
- Fixed a re-entrant candidate-panel synchronization bug: updating the visible `IMKCandidates` selection could call back into `candidateSelectionChanged(_:)` and recursively resync the panel, which could leave the input-source UI spinning or unresponsive during live typing.
- Cleaned up the install script's `TISEnableInputSource` verification snippet so the post-install step no longer emits a misleading forced-cast warning.

### Expected Usage

- Add a new dated section for each meaningful coding session.
- Record architecture changes, interface changes, and follow-up work.
- Keep this file short and factual.
