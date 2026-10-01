## ADDED Requirements

### Requirement: Rewrite With a Hotkey
Pressing ⌃⌥R with no composition SHALL offer AI actions for the selection or, with nothing selected, for the line before the cursor. The actions SHALL be 转成英文, 润色, 更正式, 更简洁, and 转成中文. The result SHALL be shown before any text changes; `Return` SHALL replace the target text and `Esc` SHALL keep it.

#### Scenario: Chinese line in a chat app
- **WHEN** the user types 这个功能下周上线，麻烦大家帮忙回归一下 in SeaTalk and presses ⌃⌥R then `Return`
- **THEN** the popup SHALL show 转成英文 running and then an English result, and `Return` SHALL replace the line with it

#### Scenario: Cancel while running
- **WHEN** the user presses `Esc` while Codex is running
- **THEN** the request SHALL stop, and no text SHALL change

### Requirement: Suggestion Chip
After a mostly Chinese sentence ending in punctuation, in an app where the user writes mostly English, the input method SHALL show "✨ 转成英文 ⇥" next to the caret for 6 seconds. `Tab` SHALL run 转成英文 on that sentence; any other key SHALL dismiss the chip and be handled normally. Chips SHALL appear at most once a minute per app and SHALL pause in an app for a day after three dismissals.

#### Scenario: English app
- **WHEN** the user's profile for GitHub in Chrome is 90% English and they type 这里需要加一个超时。
- **THEN** the chip SHALL appear and `Tab` SHALL start the rewrite

#### Scenario: Chinese app
- **WHEN** the user types the same sentence in an app where they write mostly Chinese
- **THEN** no chip SHALL appear

### Requirement: Only Confirmed Text Leaves the Mac
Only the text of an action the user confirmed SHALL be sent to the AI provider, with the action's instruction. The memory, the journal, field context, and window titles SHALL NOT be sent. No AI action SHALL run in excluded apps or under secure input.

#### Scenario: Chip ignored
- **WHEN** a chip appears and the user keeps typing
- **THEN** nothing SHALL be sent

### Requirement: Codex Provider
The provider SHALL run `codex exec` ephemerally with a read-only sandbox in an empty working directory, passing the prompt on stdin, with the configured model (default `gpt-6-luna`, low reasoning effort) and a 30 s timeout. A missing binary, a timeout, or a failure SHALL show a message, not change text.

#### Scenario: Codex not installed
- **WHEN** no codex binary is found
- **THEN** ⌃⌥R SHALL show "未找到 Codex" with how to set `AICodexPath`
