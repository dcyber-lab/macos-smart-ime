## Context

`SelectionTranslationController` translates the selection English → Simplified Chinese through `AppleSelectionTranslator` and shows `TranslationPopup`. The hotkey (`⌃⌥T`) is hard-coded in `IMEInputController`. Both English → Chinese and Chinese → English models are installed on the development machine; direct framework calls take about 100–200 ms. A mostly Chinese selection translated "from English" is returned unchanged.

## Goals / Non-Goals

**Goals:**
- Translate either direction without the user choosing one.
- Let users disable the feature or move the hotkey.
- Record the feature as supported and state the rule it follows.

**Non-Goals:**
- Languages other than English and Simplified Chinese.
- A settings UI (planned for the Companion app); settings use `defaults write`.
- Coverage outside SmartIMEHost or in apps that do not report their selection.

## Decisions

### 1. Direction by Han characters versus English words
Count Han characters (CJK Unified Ideographs, U+4E00–U+9FFF and extension A) and English words (runs of Latin letters). Translate Simplified Chinese → English when there is at least one Han character and Han characters ≥ English words; otherwise English → Simplified Chinese. Comparing against letters would misroute Chinese sentences with English terms: "你好meetinghellowomen测试he 数据库GitHub" has 7 Han characters but 25 letters (3 words). A 2× weighting was tried first and misrouted "这个feature要deploy到production" (4 Han characters, 3 words). Examples: that sentence (4 ≥ 3) → 中 → 英; "Let's discuss 数据库 design" (3 < 4) → 英 → 中; "Please use 飞书 for the meeting" (2 < 5) → 英 → 中. Alternative considered: `NLLanguageRecognizer`; it is heavier and less predictable on short mixed selections.

### 2. Direction-aware translator
`SelectionTranslator.translate(_:direction:)`; `AppleSelectionTranslator` checks availability for the chosen pair and throws `modelNotInstalled(direction)`. The popup label and the missing-model message name the pair.

### 3. Settings in the defaults domain
`SelectionTranslationSettings` reads `UserDefaults.standard` in the host process (domain `lab.dcyber.inputmethod.smartime`) each time a key is checked, so `defaults write` takes effect without restarting the input method. The hotkey string is `modifier+modifier+letter` with `ctrl`/`control`, `option`/`alt`, `cmd`/`command`, `shift`, and one letter `a`–`z`; at least one of ctrl, option, or cmd is required so plain typing is never captured. Invalid strings fall back to `ctrl+option+t`.

### 4. Architecture rule
The IME may run explicit, user-triggered, asynchronous, on-device actions (like selection translation). It still must not run AI, network calls, or long-running work per keystroke or in the composition path. `docs/technical-design.md` records this and keeps Companion as the home for app-independent features.

## Risks / Trade-offs

- [Short mixed selections can pick the wrong direction] → Half-and-half goes to Chinese → English only when Han characters dominate; the popup label makes the direction visible, and Escape leaves the text unchanged.
- [Hotkey conflicts with an app's shortcut] → Configurable; the IME only captures it while SmartIMEHost is active and nothing is being composed.
- [Settings without UI] → Documented `defaults write` commands; a UI comes with Companion.
