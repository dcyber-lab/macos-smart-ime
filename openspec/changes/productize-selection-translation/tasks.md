## 1. Direction

- [x] 1.1 Add `TranslationDirection` with script-share detection and tests (English, Chinese, mixed, empty)
- [x] 1.2 Make `SelectionTranslator` direction-aware; update `AppleSelectionTranslator`, controller state, messages, and popup label; update tests

## 2. Settings

- [x] 2.1 Add `SelectionTranslationSettings` (enabled flag, hotkey parser with fallback) with tests
- [x] 2.2 Use the settings for hotkey matching in `IMEInputController`, read on each key so `defaults write` applies immediately

## 3. Verification and Docs

- [x] 3.1 Add a Chinese → English replacement check to the smoke test; run `scripts/ime/dev-cycle.sh`
- [x] 3.2 Update `docs/technical-design.md` (supported feature, IME rule), `docs/ime-manual-validation.md` (both directions, settings), and `docs/implementation-log.md`; mark the POC change's docs accordingly
