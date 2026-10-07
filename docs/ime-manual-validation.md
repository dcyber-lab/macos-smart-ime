# IME Manual Validation

This document is the repository-owned checklist for installing and manually validating the current `SmartIMEHost` milestone.

## Prerequisites

- Full Xcode is installed and active through `xcode-select`
- `xcodegen` is installed
- `librime` is installed through Homebrew: `brew install librime`
- The repository includes the project Rime schema under `third_party/librime-data/smartime`

## Build

Run:

```bash
scripts/ime/build-host.sh
```

Expected result:

- `build/ime-host/Products.noindex/SmartIMEHost.app` exists
- the built bundle is ad-hoc signed
- the main executable is not a Debug `@rpath/...debug.dylib` wrapper

The first build downloads the rime-ice Chinese tables (about 28 MB, SHA-256 verified) into `build/rime-data/`; later builds reuse them. See `third_party/librime-data/smartime/NOTICE.md` for licensing.

## Install

```bash
./install.sh          # install, or update an existing install
./install.sh --pull   # pull the latest code first
./install.sh --test   # also run the automated smoke test
```

The script checks for Xcode and Homebrew, installs `librime` and `xcodegen` when missing, builds, and installs into `/Library/Input Methods`. The first install asks for the administrator password once and hands the bundle to the current account (`scripts/ime/enable-dev-install.sh`), so updates need no password. Trade-off: any process running as that account can modify the installed input method; `sudo scripts/ime/install-host.sh --system` restores `root:wheel` ownership.

Build output lives in `*.noindex` folders (`build/ime-host/Products.noindex`, `DerivedData.noindex`). Spotlight indexes app bundles anywhere else and registers them with LaunchServices, and `imklaunchagent` then fails to launch the input method from that copy (`LaunchInputMethod() Error, status=-50`), so typing does nothing.

To remove the install later:

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
13. With nothing composed, press Shift+`=` and confirm `+` is inserted (not `=`); press Shift+`/` and confirm `？`
14. Type `nihao` and press Shift+`1`, and confirm `你好！` is inserted
15. With nothing composed, type Shift+`h` then `ello` and confirm the composition shows `Hello` with no candidates; press `Space` and confirm `Hello` is inserted
16. Type `yunyuansheng`, `neijuan`, and `fupan` and confirm 云原生, 内卷, and 复盘 are the first candidates (rime-ice vocabulary)

This milestone is not considered complete until steps 5 through 16 are verified in a real macOS text client with the visible candidate panel.

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
19. Switch back to Chinese mode, type `neihekongj`, and confirm 内核空间 is first and `kernel space` appears after the Chinese candidates
20. Type `neihe` and confirm the translations after 内核 are `kernel` then `core`
21. Type `rongqi` and confirm `container` appears after 容器; type `cangku` and confirm `repository` then `warehouse` after 仓库

This milestone is not considered complete until steps 1 through 21 are verified in a real macOS text client.

Picks change English placement (see the next checklist), so run this checklist on a fresh history: quit the input method's process after `rm ~/Library/Application\ Support/SmartIMEHost/candidate-history.json`.

## Candidate Learning Checklist

Start from a fresh history as above, in Chinese mode unless noted.

1. Type `gith`, press `2` to commit `GitHub`; type `gith` again and confirm `GitHub` is first and `Space` commits it
2. Type `shujuku`, pick `database`; type `shujuku` again and confirm `database` is second and `Space` still commits 数据库
3. Pick `database` for `shujuku` twice more; confirm `database` is then first
4. Type `hello`, press `2` to commit the first Chinese candidate; type `hello` again and confirm Chinese is first and `hello` second
5. In English mode, type `dep`, pick `deployment`; type `dep` again and confirm `dep` is still first and `deployment` second
6. Confirm `candidate-history.json` holds only English words and typed inputs (no Chinese text) a few seconds after the last pick
7. Delete the file, restart the input method, and confirm the orders above are back to the defaults

## Translation Learning Checklist

Requires macOS 26 and the English and Simplified Chinese translation languages (System Settings › General › Language & Region › Translation Languages). Use TextEdit in Chinese mode. Start fresh with `rm ~/Library/Application\ Support/SmartIMEHost/{translation-misses.json,user-translations.tsv}` and then quit the input method's process. To watch runs: `log stream --predicate 'process == "SmartIMEHost"' | grep "translation learning"`.

1. Type `huiduhuanjing`, confirm 灰度环境 has no English candidate, and commit it with `Space`; repeat twice more (three commits)
2. Switch to another app and back, and confirm the log shows "translation learning kept 1" (or "rejected 1")
3. If kept, type `huiduhuanjing` and confirm its English appears after the Chinese candidates; `user-translations.tsv` has the line under "# Learned automatically"
4. Commit two more words without a translation three times each, switch apps again, and confirm nothing runs (less than a day since the last run)
5. Run `defaults write lab.dcyber.inputmethod.smartime TranslationLearningInterval -int 60`, wait a minute, switch apps, and confirm the two words are tried
6. Add a line `内核<TAB>OS kernel` to `user-translations.tsv`, switch apps, type `neihe`, and confirm the only translation is `OS kernel`
7. Delete the 灰度环境 line, switch apps, commit 灰度环境 three more times, and confirm it gets no translation and is not tried again
8. Run `defaults write lab.dcyber.inputmethod.smartime TranslationLearningEnabled -bool false`, commit a new untranslated word, and confirm `translation-misses.json` does not gain it
9. Clean up: `defaults delete lab.dcyber.inputmethod.smartime TranslationLearningInterval` and `defaults delete lab.dcyber.inputmethod.smartime TranslationLearningEnabled`
10. Note how many words were kept versus rejected; the round-trip check has not been measured with the real translation models yet

## Selection Translation Checklist

Requires macOS 26 and the English and Simplified Chinese translation languages (System Settings › General › Language & Region › Translation Languages). Use TextEdit or Notes with SmartIMEHost active.

1. Type or paste an English sentence and select it
2. Press `⌃⌥T` and confirm a popup below the selection shows an "EN → ZH" badge before the selected text, then the Chinese translation with "⏎ 替换 · Esc 取消", and that the selected text does not touch the popup's right edge
3. Press `Return` and confirm the selection is replaced by the translation
4. Select a Chinese sentence (for example 请在周五前审阅部署计划), press `⌃⌥T`, and confirm the popup shows "ZH → EN" and an English translation
5. Select English again, press `⌃⌥T`, then `Escape`, and confirm the text is unchanged
6. Press `⌃⌥T` with nothing selected and confirm the popup says "Select the English text to translate first"
7. While composing pinyin, press `⌃⌥T` and confirm nothing happens
8. Run `defaults write lab.dcyber.inputmethod.smartime SelectionTranslationHotkey "cmd+shift+y"`, confirm `⌘⇧Y` translates and `⌃⌥T` no longer does; then `defaults delete lab.dcyber.inputmethod.smartime SelectionTranslationHotkey`
9. Run `defaults write lab.dcyber.inputmethod.smartime SelectionTranslationEnabled -bool false`, confirm the hotkey does nothing; then `defaults delete lab.dcyber.inputmethod.smartime SelectionTranslationEnabled`

## Automated Smoke Test

`./install.sh --test` builds and installs the host, then runs the smoke test (`scripts/ime/build-e2e.sh` builds it from `scripts/ime/e2e/`):

- `SmartIMETestClient.app` is a throwaway window with one text view. It never opens documents or writes anywhere except a temporary state directory, so the test cannot touch the user's apps or files.
- `SmartIMEDriver` waits until the keyboard and mouse have been idle for 5 seconds, posts synthetic keys only to the test client, and checks the committed and marked text: Space, number keys, translation, Return, Escape, raw preedit for `good`, the Shift toggle, a row click, `gith` + 2, and selection translation (popup opens, Escape keeps the text, and with the models installed Return replaces Chinese → English and English → Chinese). It prints the live panel size.
- It aborts on a real key press or when the test window loses focus, restores the previous input source and app, and exits non-zero on any failure.

Run it after every change to the IME host before hand-off.

## Candidate Panel Checklist

Use a normal editable text field such as TextEdit.

1. In light appearance, type `shujuku` in Chinese mode
2. Confirm a rounded vertical panel appears just below the caret with the pinyin (`shu ju ku`) in gray text at the top above a hairline, numbered rows, 数据库 highlighted with a solid accent-color fill and white text, a separator line above `database`, and a capsule 译 tag on `database`
3. Confirm a dimmed up chevron and a normal down chevron appear next to the pinyin; press `=` and confirm both chevrons are normal on page 2, and that they do not move while paging
4. Confirm the panel is exactly as tall as its rows, with no empty space below; type `huiyi` and confirm the panel resizes
5. Press `Down` twice and confirm the highlight moves to the third row; with `database` highlighted, confirm its TR tag stays readable (white on the accent fill)
6. Click the `database` row and confirm `database` is committed and the panel disappears
7. Type `hello` and confirm `hello` is first with an EN tag and a separator below it
8. Press `Shift` to switch to English mode, type `he`, and confirm the rows have no tags or separators
9. Switch the system to dark appearance and repeat step 1; confirm the panel background and text follow dark colors
10. Move the caret near the bottom and the right edge of the screen and confirm the panel flips above the caret and stays fully on screen
11. Type `nihao`, press `Escape`, and confirm the panel disappears and nothing is inserted; type again, switch to another app, and confirm the panel does not stay behind

This milestone is not considered complete until steps 1 through 11 are verified in a real macOS text client.

## Commit Effects Checklist

1. In TextEdit, type `nihao` and press `Space`: 你好 is inserted at once, its row bursts into rainbow shards, and the rest of the panel fades out
2. Type `nihao` and press `4`: the 4th row (not the highlighted one) breaks apart
3. Type `nihao` then `，`: the 你好 row breaks apart, not the 你 row
4. Type `nihao` and press `Return` with raw pinyin, and press `Escape` on another composition: nothing breaks apart
5. Switch to English mode, type `deplo`, press `Down` and `Space`: the deploy row breaks apart
6. Type quickly (`wo` `Space` `men` `Space` …): every new panel appears at once and fully visible; fragments fly over it and fade
7. Open the input menu › Settings… › Appearance: choosing a motion or palette plays a preview below the pointer and the next commit uses it; Play replays it. Try every motion and palette, Random (changes per commit), and Off (no effect; Fragment colors and Play are grayed out)
8. Turn on System Settings › Accessibility › Display › Reduce motion: commits play no effect; turn it off again
9. Repeat step 1 in dark appearance

## Intelligence Hub Checklist

1. Open the input menu: Intelligence Learning is unchecked and Don't Learn in <current app> names the app you are typing in. In Settings… › Intelligence, Save typed text is grayed out
2. Turn on Intelligence Learning in the menu; the open settings window follows, and Save typed text becomes available and checked
3. Type 这个功能下周上线。 in one app and Please review it. in another
4. Choose View Learning Data…: a page opens in the browser with both apps' Chinese/English mix, 2 fingerprints, and both sentences; searching 上线 leaves only the first
4a. The page starts with What it learned: type 麻烦大家帮忙回归一下 three times and 明天下午三点开会, reopen the page, and confirm the sentence appears under Repeated sentences (3 次) and the meeting under 提到时间的句子
4b. In Notes, type 发布计划, press Return, type 这个功能下周上线。; the page shows that sentence with Context: 发布计划, groups sentences into sessions, and lists Notes under 读取前文的开销 with a few ms
4c. Type lo in Alfred or Raycast; it is not recorded
4d. In Settings… › Intelligence, turn on Read window titles: the system asks for Accessibility access and the Privacy & Security pane opens; switch on LinguaType (after an update, switch it off and on). Back in the window, the Accessibility permission is required row is gone
4e. Type a sentence in Chrome on two different tabs and in an editor; the page shows separate sessions with the window titles, and the 窗口标题 table shows sample titles and timings per app
5. Type 验证码是 482913。 and a sentence in Terminal; the first appears as 验证码是 〔数字〕。 and the Terminal one not at all
5a. In a chat app, type part of a message, switch away to copy a link, paste it, type 10mins 内完成, and press Return; the page shows the whole message with 〔链接〕 and 10mins
6. Choose Don't Learn in <app> for the first app, type another sentence there, and confirm it is not recorded
7. Turn off Save typed text, type a sentence, and confirm the journal does not gain it while the app's counts still grow
8. In Settings… › Intelligence, choose Clear…, confirm the alert, and check that `~/Library/Application Support/SmartIMEHost/` no longer has `input-memory.json`, `journal/`, `candidate-history.json`, or `translation-misses.json`

## Input Menu and Settings Window Checklist

1. Open the input menu in TextEdit: below LinguaType there are only Intelligence Learning, Don't Learn in TextEdit, Enable AI Hints in TextEdit, View Learning Data…, and Settings…; each one changes something (check with `defaults read lab.dcyber.inputmethod.smartime`)
2. Choose Settings…: the window opens in front, titled after the pane; switching panes resizes it
3. With Ollama stopped and 模型 set to Ollama, the status says no model can run and the menu's AI 提示 item is grayed out unless it is already on
4. Press ⌘W (and, after reopening, Esc): the window closes and TextEdit has focus again, so typing continues there
5. Choose Settings… again while the window is behind another app: the same window comes to the front

## AI Assist Checklist (proof of concept)

1. Open Notes (or TextEdit), open the input menu, and choose Enable AI Hints in Notes; Settings… › AI Assistant lists Notes and its status line names the model in use
2. Type 这个功能下周上线，麻烦大家帮忙回归一下。: a chip "✨ 转成英文 · 生成中… ⇥" appears below the caret, then after about 7–9 s an English preview
3. Press Tab (or →, needed in Sublime Text): the sentence is replaced by the English text and the chip says 已替换
4. Type another sentence and press Tab before the preview appears: it is replaced as soon as the result arrives
5. Type another sentence and keep typing: the chip disappears and nothing is replaced
6. In an app that was not enabled, type the same sentence: no chip appears
7. In Chrome (a GitHub comment box) and SeaTalk, enable AI 提示 and repeat 2–3; note whether the text is replaced or copied (⌘V)
8. Turn Intelligence Learning off and repeat 2: the chip still appears in the enabled app
9. With a preview showing, press ⇧→ or ⌥→: the chip disappears, the cursor moves or the selection grows, and nothing is replaced

## AI Rewrite (⌃⌥R) Checklist

1. In any text field, type 这个功能下周上线，麻烦大家帮忙回归一下 (no punctuation) and press ⌃⌥R: a popup lists 1 转成英文 … 5 转成中文 with "⏎ 转成英文"
2. Press Return: it shows 生成中… and then the English text; press Return again to replace the line
3. Select an English sentence, press ⌃⌥R then 2: the popup shows the polished sentence; Esc keeps the original
4. In SeaTalk, type a message, press ⌃⌥R and Return twice before sending; the message is replaced (or copied, ⌘V, if the app refuses)
5. In Ghostty, press ⌃⌥R with nothing selected: the popup says the app does not provide its text
6. Type 这个接口有问题 followed by two spaces, then press ⌃⌥R and Return twice: the whole line, and nothing before it, is replaced
7. With a result showing, click into another text field of the same app: the popup closes, and Return there does not replace anything
8. In an empty field (or on a new blank line), press ⌃⌥R: the popup says there is nothing to rewrite; it never shows the clipboard

## Screenshot Checklist

1. Press ⌃⌥A: macOS asks for Screen Recording access. Allow LinguaType in System Settings › Privacy & Security › Screen & System Audio Recording, choose Quit & Reopen, then press ⌃⌥A again. Settings… › Screenshot shows Granted
2. Move the pointer over windows: each one is highlighted and the magnifier shows position and color. Click: that window is selected and the toolbar appears below it
3. Right click, then drag out a rectangle: the size label shows its pixels; drag inside to move it and drag a grip to resize it
4. Choose 矩形, 箭头, 画笔, 马赛克 and 文字 in turn and mark the selection; change size and color; ⌘Z removes the last mark
5. Press Return: the toast says 已复制Screenshot. Paste into Notes or a chat: the image has the marks and its on-screen size
6. Capture again and press ⌘S: the file appears in the save folder (desktop by default) as Screenshot <date time>.png
7. Capture again and click 贴图: the capture floats where it was. Drag it, scroll to zoom, right click › 识别文字并复制, then double-click to close it
8. Press ⌃⌥O, drag over a paragraph with Chinese and English: the overlay closes and the toast says 已复制识别的文字（N 字）. Paste: the lines read in order
9. With two displays, press ⌃⌥A and select on the second display; with a full-screen app in front, press ⌃⌥A: the overlay covers it
10. Press Esc during each step: the overlay closes and the app you were in has the keyboard again
11. Turn Screenshot shortcut off in Settings… › Screenshot: ⌃⌥A, ⌃⌥O and ⌃⌥⇧A reach the app in front again

## Screen Recording Checklist

1. Press ⌃⌥⇧A: the overlay says to select the area to record. Click a window: the toolbar shows only cancel and a red record button
2. Press Return: the overlay closes, the app you were in has the keyboard, a red frame surrounds the area, and the bar below it counts up
3. Type, scroll, and move windows in the area for about 10 seconds, then leave the screen still for 5 seconds
4. Click the bar's stop button: the toast says the file was saved and copied. The file `Screen Recording <date time>.mp4` is in the save folder; paste it into a chat or Finder
5. Play it in QuickTime: about 15 seconds, the pointer is visible, the frame and the bar are not, the still ending is kept, the size matches the area
6. Record again and stop with ⌃⌥⇧A; while recording, press ⌃⌥A: only a toast, no overlay
7. Press ⌃⌥A, select an area, click the record button in the toolbar: the same area is recorded
8. Record the whole screen on a Retina display: the video is at full pixel size (scaled to 4K at most), and the bar sits inside the area but is not in the video
9. Settings… › Screenshot › Recording frame rate 60: a new recording plays at 60 fps (QuickTime › Window › Show Movie Inspector)
10. Unplug the second display while recording on it: recording stops, the toast says why, and what was recorded plays
11. Record for 30 minutes with normal work in the area: the bar keeps counting, typing stays smooth, and the file plays to the end
12. Start a recording, wait 10 seconds, then run `killall SmartIMEHost` in Terminal: the file in the save folder plays up to about 2 seconds before the kill

## Clipboard History Checklist

1. Copy a few lines of text in Notes, an image in Preview, and a command in Terminal. Press ⌃⌥V: the panel opens centered, newest first, with each entry's app icon; the image row reads 图片：宽×高（大小）
2. Press ↓ and ↑: the right side previews the text in full, or the image; the caption shows time, app, and size
3. Type a word: the list narrows to entries containing it; clear it and everything returns
4. Click into a text field in another app, press ⌃⌥V, then ⏎ (or ⌘2): the panel closes and the text is pasted there. Without Accessibility access the toast says 已复制，按 ⌘V 粘贴
5. Choose an image into Notes or a chat: the image is pasted
6. ⌘P pins an entry (pin icon, stays on top); ⌘⌫ deletes the selected one
7. Copy a password from a password manager: it does not appear in the list
8. Click outside the panel or press Esc: it closes and the app you were in has the keyboard again
9. Settings… › Clipboard: Keep for changes the period, Clear… keeps pinned entries, turning Clipboard history off stops recording and ⌃⌥V reaches the app in front again; Shortcuts can rebind it

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
