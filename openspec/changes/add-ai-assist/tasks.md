## 0. Proof of Concept

- [x] 0.1 `CodexRewriter` (lookup, ephemeral read-only `codex exec`, stdin prompt, `-o`, 30 s timeout, cancel) with stub-binary tests; checked against the real codex: 7–9 s
- [x] 0.2 `AIAssistChipController` (offer, prefetch, Tab before or after the result, dismiss and cancel, one offer per app every 5 seconds) with fake-provider tests
- [x] 0.3 `SuggestionChip` panel; offers from `IntelligenceRecorder.onFieldSentence`; replacement with read-back and clipboard fallback
- [x] 0.4 Menu: 在「App」中启用 AI 提示 (per app, off by default), provider choice, status
- [x] 0.6 `AppleRewriter` (on-device, default when available) with per-action output fields; checked against the real model
- [ ] 0.5 Live: Notes or TextEdit, Chrome (GitHub), SeaTalk

## 1. Provider

- [ ] 1.1 `AIProvider` protocol and `CodexProvider` (binary lookup, arguments, stdin, `-o`, timeout, cancel, errors), tested with a stub binary script
- [ ] 1.2 Prompts per action, text wrapped as data

## 2. Rewrite Flow

- [x] 2.1 `AIRewriteController` state machine with tests (fake provider: defaults, digits, cancel, stale results, errors)
- [x] 2.2 Popup: action list, running, result, messages (`TranslationPopup.show(_: AIRewriteController.State)`)
- [x] 2.3 ⌃⌥R in `IMEInputController`: selection or line before the cursor, replacement with clipboard fallback

## 3. Suggestion Chip

- [ ] 3.1 Chip rules (language share, app profile, rate limit, dismissals) as a pure function with tests
- [ ] 3.2 `SuggestionChip` panel; `Tab` accepts, other keys dismiss and pass through, 6 s timeout
- [ ] 3.3 Trigger from `IntelligenceRecorder` sentence ends

## 4. Settings, Menu, Docs

- [ ] 4.1 `AIAssistSettings` and the AI 助手 menu section with provider status
- [ ] 4.2 Docs: hub exception for confirmed text, technical design, validation checklist, log
- [ ] 4.3 CI; live check in SeaTalk, Chrome (GitHub), Notes

## 5. Ollama Provider

- [x] 5.1 `OllamaRewriter`: `POST /api/chat` on `AIOllamaURL` (default `http://localhost:11434`), model `AIOllamaModel` (default `qwen2.5:3b`), temperature 0, `keep_alive` 30 m, 15 s timeout; output cleaned like the on-device free-text answer
- [x] 5.2 Availability: `GET /api/tags` lists the model (0.4 s timeout, cached 30 s)
- [x] 5.3 `Provider.ollama`; `auto` order ollama → Apple → Codex; menu entry and status text
- [x] 5.4 Prompts shared with the on-device model (terms, English style examples), tested with a stub HTTP server
- [x] 5.5 Docs and log: why (Qwen2.5-3B measured 0.1–0.3 s per sentence, better zh→en than the on-device model, no guardrail refusals), how to install (`ollama pull`, or a GGUF from Hugging Face when the registry is slow)
