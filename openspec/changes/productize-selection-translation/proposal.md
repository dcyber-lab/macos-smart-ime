## Why

The in-IME selection translation proof of concept (`add-selection-translation-poc`) works end to end, and the user wants it as a regular feature. As a POC it only translates English to Chinese (mostly Chinese selections come back unchanged), has a fixed hotkey, cannot be turned off, and is documented as an exception to the architecture.

## What Changes

- Detect the translation direction from the selection: when Han characters outweigh English words (Han characters ≥ English words) → Simplified Chinese to English, otherwise English to Simplified Chinese. The popup label shows the direction (中 → 英 or 英 → 中).
- Add settings in the input method's defaults domain (`lab.dcyber.inputmethod.smartime`): `SelectionTranslationEnabled` (default on) and `SelectionTranslationHotkey` (default `ctrl+option+t`; modifiers plus one letter). Invalid values fall back to the default.
- Promote the feature from POC to a supported IME feature: user-triggered, asynchronous, on-device actions are allowed in the IME; per-keystroke work still is not. The Companion app remains the future home for app-independent coverage.

## Capabilities

### New Capabilities
- `translation-direction`: choosing English → Chinese or Chinese → English from the selected text.
- `translation-settings`: enabling the feature and choosing its hotkey.

### Modified Capabilities
- (None)

## Impact

- `apps/ime/Sources/IMEHostCore`: `TranslationDirection`, direction-aware `SelectionTranslator`, `SelectionTranslationSettings` with a hotkey parser, controller and popup label changes, hotkey matching in `IMEInputController`.
- Docs: `docs/technical-design.md` (supported feature and boundary rule), `docs/ime-manual-validation.md`, `docs/implementation-log.md`.
- Smoke test gains a Chinese → English replacement check.
