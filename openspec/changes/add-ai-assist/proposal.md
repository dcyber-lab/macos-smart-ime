## Why

The intelligence hub learns locally (`add-input-memory`, `add-window-context`). The user now wants the first AI help. They chose their Codex subscription as the provider for now; Apple Intelligence is off on this Mac. This accepts one exception to "local only": the text of an action the user confirms is sent to Codex (OpenAI). Learned memory, the journal, context, and window titles are never sent.

## Proof of concept first (user request, 2026-10-01)

The user asked to try the chip before the full change. The POC implements:
- **The chip, 转成英文 only.** It shows in apps the user turns on from the menu (在「App」中启用 AI 提示), for sentences ending in punctuation that are mostly Chinese (Han characters against English words) and 6+ characters long.
- **Prefetch.** The sentence is sent to Codex as soon as the chip shows, so the result is usually ready when the user reacts. In enabled apps, qualifying sentences therefore leave the Mac before confirmation. The user accepted that for the POC by asking to see the effect; it is why chips are opt-in per app and not driven by the learned English profile.
- **Applying the result.** `Tab` replaces the sentence through `insertText(_:replacementRange:)` and checks the result; if the app did not take it, the text is copied to the clipboard. `Tab` before the result arrives replaces it on arrival. `Esc` or any other key dismisses the chip and stops the request.

- **Pacing.** At most one chip per app every 5 seconds. The first build used one per minute, and a dismissed chip then blocked a minute of test sentences.

⌃⌥R, the other actions, the English-profile rule, and dismissal back-off follow after the POC.

## What Changes

- **⌃⌥R: rewrite with AI.**
  - Works on the selection or, with nothing selected, on the line before the cursor.
  - A popup lists actions: `1 转成英文 2 润色 3 更正式 4 更简洁 5 转成中文`. `Return` picks the default: 转成英文 for Chinese, 润色 otherwise.
  - The popup then shows "✨ Codex 思考中… Ns". `Esc` cancels and stops the request.
  - The result is shown before anything changes. `Return` replaces the text; `Esc` keeps the original.
- **✨ chip: a suggestion after a sentence.**
  - After a sentence ending in punctuation that is mostly Chinese, in an app where the user writes mostly English (learned profile), a chip "✨ 转成英文 ⇥" appears next to the caret for 6 seconds.
  - `Tab` runs 转成英文 on that sentence, the same way as ⌃⌥R. Any other key dismisses the chip and is typed normally.
  - At most one chip per app per minute. After 3 dismissals in an app, chips pause there for a day.
- **Provider: Codex CLI.**
  - `codex exec` runs ephemeral, with a read-only sandbox, in an empty working directory, using `gpt-6-luna` at low reasoning effort (about 6–7 s measured).
  - The text goes in on stdin and the result comes back through `-o`, with a 30 s timeout.
  - A provider protocol leaves room for Apple Intelligence and `claude -p`.
- **Input menu, new section AI 助手:**
  - AI 提示 toggle (on by default);
  - the hotkey (info);
  - the provider status: Codex found or missing, the model, and a note that confirmed text is sent to OpenAI.
- **Settings**: `AIAssistEnabled`, `AIAssistChipsEnabled`, `AIAssistHotkey` (default `ctrl+option+r`), `AICodexPath`, `AICodexModel`, `AICodexReasoningEffort`.

## Non-goals

- Calendar and quick-phrase suggestions (no AI; next changes).
- "Help me reply" with the conversation as context (needs per-app chat reading, use-without-storing).
- Intercepting `Return` in chat apps: a chip after sending is too late, so ⌃⌥R before sending is the chat workflow.
- Apple Intelligence or `claude -p` providers.

## Capabilities

### New Capabilities
- `ai-assist`: the rewrite hotkey, the suggestion chip, what is sent where, and how results are applied.

## Impact

- New in `IMEHostCore`:
  - `AIAssistController` (state machine, tested with a fake provider);
  - `AIProvider` and `CodexProvider` (process, timeout, cancel);
  - `AIAssistSettings`;
  - `SuggestionChip` (panel);
  - `AIAssistMenu`.
- `IMEInputController`: hotkey, chip trigger after sentences (from `IntelligenceRecorder`), `Tab` handling while the chip shows, and text replacement.
- `TranslationPopup` gains the action list and the running state, or gets a sibling popup in the same style.
- Docs: `docs/intelligence-hub.md` (the exception for confirmed text), `docs/technical-design.md`, `docs/ime-manual-validation.md`, `docs/implementation-log.md`.
