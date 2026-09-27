## Why

The user wants to turn selected English sentences into Chinese without leaving the text field. The planned home for selection-level operations is the Companion app, which does not exist yet; the user asked for a quick in-IME proof of concept first to judge the experience.

## What Changes

- While SmartIMEHost is the active input source and nothing is being composed, `⌃⌥T` translates the selected English text into Simplified Chinese.
- Translation runs on-device with Apple's Translation framework (`TranslationSession(installedSource:target:)`, macOS 26), asynchronously, so typing is never blocked.
- A small popup near the selection shows "翻译中…", then the translation with the hint "⏎ 替换 · Esc 取消". `Return` replaces the selection with the translation, `Escape` or any other key dismisses it.
- Clear messages instead of a result when nothing is selected, the client cannot report its selection, the English → Simplified Chinese model is not downloaded, or the system is older than macOS 26.
- Proof of concept: documented as an exception to "the IME only does real-time typing" and expected to move to the Companion app.

## Capabilities

### New Capabilities
- `selection-translation`: hotkey, selection reading, on-device translation, popup, replacement, and error messages for the in-IME POC.

### Modified Capabilities
- (None)

## Impact

- `apps/ime/Sources/IMEHostCore`: `SelectionTranslationController` (state machine), `SelectionTranslator` protocol with an Apple Translation implementation, `TranslationPopup` panel, and hotkey routing in `IMEInputController`.
- Links the system `Translation` framework (weakly, since the deployment target is macOS 13).
- The user must download the English and Simplified Chinese translation languages once (System Settings › General › Language & Region › Translation Languages).
- `docs/technical-design.md` records the POC exception to the IME/Companion boundary.
