## Context

Selection translation already has the pieces this change reuses:
- a hotkey checked in `handle(_:client:)`;
- the selection read through IMK (`selectedRange`, `attributedSubstring(from:)`);
- an async state machine (`SelectionTranslationController`) driving `TranslationPopup`;
- `Return` replacing the captured range with `insertText(_:replacementRange:)`.

`IntelligenceRecorder` knows when a sentence ends and what it is. `InputMemory` knows each app's Chinese share. Codex was measured on this Mac: `gpt-6-luna` at low effort answers in 6–7 s, and `gpt-6-sol` by default in 10–12 s.

## Decisions

### 1. Explicit first, suggestion second

AI is slow (seconds), so it never runs on its own.
- **⌃⌥R** is the general entry point and works in every app, including chat apps before sending.
- The **chip** only offers ⌃⌥R's most useful action at the moment it is most likely wanted. Accepting it runs the same flow.

### 2. Target text and range

- **With a selection**: the selection and its range, as in selection translation.
- **Without a selection, ⌃⌥R**: the line before the cursor, read like the recorder's field read. In Chromium apps that read is about 100 characters, so a longer message needs a selection; the popup says so when the line looks cut. The range is `[cursor − line length, cursor)`.
- **The chip**: the sentence that just ended, ending at the cursor. Its range is `[cursor − sentence length, cursor)`, valid while the cursor has not moved. Any other key dismisses the chip, so `Tab` always sees the same cursor.
- **Replacing**: `Return` calls `insertText(result, replacementRange:)`. If the client then reports a different text in that range, the result is put on the clipboard and the popup says "已复制，⌘V 粘贴". Live checks decide which apps need that.

### 3. Chip rules

A chip for 转成英文 shows when all of these hold:
- AI 提示 is on;
- learning is on and the app is not excluded;
- the sentence ended with punctuation;
- the sentence has 6+ characters and at least 70% Han characters;
- the app's learned profile is at most 30% Chinese over at least 50 units;
- the app has not had a chip in the last 60 s;
- fewer than 3 chips were dismissed there in the last 24 h.

Dismissals and acceptances are kept in memory for the session. The chip is a small panel in the candidate panel's style, below the caret, for 6 s.

### 4. Codex provider

- `CodexProvider` runs the binary from `AICodexPath`, else the first of `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, and `~/.local/bin/codex`.
- Arguments: `exec --skip-git-repo-check --ephemeral -s read-only -C <empty temp dir> -m <model> -c model_reasoning_effort="<effort>" -o <temp file> -`.
- The prompt goes in on stdin, so the text never appears in a process list.
- A 30 s timeout or `Esc` terminates the process.
- The prompt states the task and wraps the text in `<text>` tags as data, not instructions. The read-only sandbox can still read files, so a crafted text could pull local content into the result. Showing the result before replacing, and the empty working directory, keep that visible and contained. This is documented.

Prompts:

| Action | Instruction |
|---|---|
| 转成英文 | natural, professional English |
| 润色 | same language, clearer and more fluent |
| 更正式 | same language, more formal |
| 更简洁 | same language, shorter |
| 转成中文 | natural Simplified Chinese |

All ask for the result only, keeping names, code, links, and placeholders like 〔链接〕 unchanged.

### 5. What leaves the Mac

Sent to Codex: only the target text and the instruction. Never sent:
- the memory or the journal;
- the field context or window titles;
- anything from excluded apps or under secure input.

The menu's provider item says that confirmed text goes to OpenAI.

### 6. State machine

`AIAssistController` (`@MainActor`) has these states: `idle`, `choosing(text, range, defaultAction)`, `running(action, text, range, startedAt)`, `result(action, original, rewritten, range)`, `message(text)`.
- It handles keys like `SelectionTranslationController`: digits, `Return`, and `Esc`; any other key dismisses and passes through.
- Stale results after a cancel are dropped.
- It is tested with a fake provider: actions, defaults, cancel, stale results, errors (Codex missing, timeout, non-zero exit).

## Risks

- **Latency**: 6–7 s per action. The running state shows elapsed seconds, and `Esc` always works.
- **Replacement**: some apps (Chromium in particular) may not honor `replacementRange` outside a composition; the clipboard fallback covers them.
- **Codex changes**: CLI flags or model names may change with updates; failures surface as messages, and `AICodexModel` can be changed with `defaults write`.
