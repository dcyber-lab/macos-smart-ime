## Context

`IMEInputController.handle(_:client:)` sees every key event while SmartIMEHost is the active input source. The client proxy (`IMKTextInput`) exposes `selectedRange()`, `attributedSubstring(from:)`, `attributes(forCharacterIndex:lineHeightRectangle:)`, and `insertText(_:replacementRange:)`. On this machine the English → Simplified Chinese on-device model reports `supported` (not yet downloaded). `TranslationSession(installedSource:target:)` is available from macOS 26; `LanguageAvailability` from macOS 15.

## Goals / Non-Goals

**Goals:**
- Select English, press `⌃⌥T`, read the Chinese, press `Return` to replace it.
- Never block typing; never send text off the device.

**Non-Goals:**
- Chinese → English, other language pairs, or auto-detecting the source language.
- Working when another input method is active, or in apps that do not report their selection (that needs the Companion app and Accessibility access).
- Downloading translation models from the IME (the system prompt needs a SwiftUI host); the popup tells the user where to download them.
- Translating while a composition is in progress.

## Decisions

### 1. Hotkey handled by the IME
`⌃⌥T` (key code 17 with exactly Control + Option, ignoring Caps Lock and Fn) is checked in `handle` before composition handling, only when nothing is being composed. It is consumed so the client never sees it.

### 2. Controller separated from UI and translation
`SelectionTranslationController` owns the state (`idle`, `translating`, `result`, `message`) and talks to a `SelectionTranslator` protocol and a presenter closure. The Apple implementation checks `LanguageAvailability().status(from: en, to: zh-Hans)` and throws a typed error for `supported` (model missing) or `unsupported`. Tests use a fake translator and presenter.

### 3. Asynchronous translation on the main actor
The controller starts a `Task` on the main actor; `translate` suspends while the framework works off the main thread. A request id discards results that arrive after the popup was dismissed or replaced by a newer request. Deactivating the input method dismisses the popup.

### 4. Separate popup, not the candidate panel
Sentences are long, and the candidate panel draws single-line rows. `TranslationPopup` is its own borderless non-activating panel (same material and corner radius as the candidate panel) with a wrapping label capped at 420 pt wide, a small line with the truncated source text, and the key hint. It is placed below the selection's first character (from `attributes(forCharacterIndex:)`), using the same placement rules as the candidate panel.

### 5. Replacement
`Return` calls `insertText(translation, replacementRange: selectedRange)` with the range captured when the hotkey was pressed, then dismisses. `Escape` dismisses. Any other key dismisses and is processed normally, so typing continues without an extra key press.

## Risks / Trade-offs

- [Breaks the "IME only does real-time typing" boundary] → Explicit hotkey only, asynchronous, documented as a POC to be moved to Companion.
- [Some apps (terminals, web views) do not report a selection through the input method] → The popup says so; the Companion version would use Accessibility.
- [The selection may change before the user presses Return] → The captured range is used; the popup is dismissed on any other key or on deactivation.
- [Model not downloaded] → Clear instructions in the popup; no automatic download.
