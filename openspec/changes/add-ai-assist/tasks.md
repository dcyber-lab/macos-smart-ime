## 1. Provider

- [ ] 1.1 `AIProvider` protocol and `CodexProvider` (binary lookup, arguments, stdin, `-o`, timeout, cancel, errors), tested with a stub binary script
- [ ] 1.2 Prompts per action, text wrapped as data

## 2. Rewrite Flow

- [ ] 2.1 `AIAssistController` state machine with tests (fake provider: defaults, digits, cancel, stale results, errors)
- [ ] 2.2 Popup: action list, running with seconds, result, messages (reuse `TranslationPopup` style)
- [ ] 2.3 ⌃⌥R in `IMEInputController`: selection or line before the cursor, replacement with clipboard fallback

## 3. Suggestion Chip

- [ ] 3.1 Chip rules (language share, app profile, rate limit, dismissals) as a pure function with tests
- [ ] 3.2 `SuggestionChip` panel; `Tab` accepts, other keys dismiss and pass through, 6 s timeout
- [ ] 3.3 Trigger from `IntelligenceRecorder` sentence ends

## 4. Settings, Menu, Docs

- [ ] 4.1 `AIAssistSettings` and the AI 助手 menu section with provider status
- [ ] 4.2 Docs: hub exception for confirmed text, technical design, validation checklist, log
- [ ] 4.3 CI; live check in SeaTalk, Chrome (GitHub), Notes
