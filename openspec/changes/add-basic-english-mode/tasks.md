## 1. English Engine Package

- [x] 1.1 Define the `EnglishInputEngine` protocol in `packages/shared-models`
- [x] 1.2 Implement a basic `EnglishInputEngine` in `packages/english-engine` that supports word buffering and candidate generation
- [x] 1.3 Add a simple word-list resource to `packages/english-engine` for completions
- [x] 1.4 Replace the hand-written word list with a 30,000-word wordfreq frequency list and a reproducible generator script
- [x] 1.5 Add `EnglishLexicon` with frequency-ranked prefix lookup, typed-text-first candidates, and Space committing the highlighted candidate
- [x] 1.6 Add `EnglishEngineTests` covering lexicon ranking, profanity exclusion, and Space/number selection

## 2. IME Host Integration

- [x] 2.1 Update `IMEInputController` to detect and handle the `Shift` key toggle for mode switching
- [x] 2.2 Integrate `EnglishInputEngine` into `IMEInputController` and `IMEHostSessionStore`
- [x] 2.3 Update `IMEInputController` to route key events to the active engine (Chinese or English) based on the current mode
- [x] 2.4 Ensure `IMKCandidates` panel works correctly for English candidates

## 3. Validation

- [x] 3.1 Verify `Shift` key toggles the mode correctly without leaking the character to the client
- [x] 3.2 Verify English typing and completion candidates appear in English mode
- [x] 3.3 Verify `Space` and number keys commit English candidates correctly
- [x] 3.4 Update manual validation checklist in `docs/` to include English mode tests
- [ ] 3.5 Re-run the English checklist in a real macOS text client with the 30,000-word lexicon
