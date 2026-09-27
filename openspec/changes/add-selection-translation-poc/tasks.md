## 1. Translation Core

- [x] 1.1 Add `SelectionTranslator` protocol and `AppleSelectionTranslator` (availability check, typed errors, macOS 26 guard); link `Translation` weakly
- [x] 1.2 Add `SelectionTranslationController` (states, request ids, replace/dismiss/other-key handling) with tests using a fake translator and presenter

## 2. UI and Host

- [x] 2.1 Add `TranslationPopup` (wrapping text, source line, key hint, messages) placed below the selection
- [x] 2.2 Route `⌃⌥T`, `Return`, `Escape`, and other keys in `IMEInputController`; read the selection through `IMKTextInput`; dismiss on deactivation
- [x] 2.3 Render the popup offscreen (loading, result, model-missing) in light and dark for review

## 3. Verification and Docs

- [x] 3.1 Run `scripts/ime/dev-cycle.sh` (existing smoke test must still pass) and add a smoke-test check that `⌃⌥T` with a selection opens the popup and `Escape` leaves the text unchanged
- [x] 3.2 Verify a real translation end to end after the model is downloaded
- [x] 3.3 Update `docs/technical-design.md` (POC exception), `docs/implementation-log.md`, and `docs/ime-manual-validation.md`
