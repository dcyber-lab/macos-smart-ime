## ADDED Requirements

### Requirement: Translate Selection with a Hotkey
While SmartIMEHost is active and nothing is being composed, pressing `⌃⌥T` SHALL translate the selected text from English to Simplified Chinese on-device and SHALL show the result in a popup near the selection. The hotkey SHALL NOT reach the client application.

#### Scenario: Selected English sentence
- **WHEN** the user selects "Please review the deployment plan." and presses `⌃⌥T`
- **THEN** a popup SHALL show "翻译中…" and then the Chinese translation with the hint "⏎ 替换 · Esc 取消"

#### Scenario: Composition in progress
- **WHEN** the user is composing pinyin and presses `⌃⌥T`
- **THEN** no translation SHALL start

### Requirement: Replace or Dismiss
`Return` SHALL replace the originally selected text with the translation. `Escape` SHALL dismiss the popup without changes. Any other key SHALL dismiss the popup and be handled normally.

#### Scenario: Replace
- **WHEN** the translation is shown and the user presses `Return`
- **THEN** the selected text SHALL be replaced by the translation and the popup SHALL close

#### Scenario: Cancel
- **WHEN** the translation is shown and the user presses `Escape`
- **THEN** the popup SHALL close and the text SHALL be unchanged

#### Scenario: Keep typing
- **WHEN** the translation is shown and the user types a letter
- **THEN** the popup SHALL close and the letter SHALL be handled as normal input

#### Scenario: Stale result
- **WHEN** the popup was dismissed before the translation finished
- **THEN** the late result SHALL be discarded

### Requirement: Clear Messages
The popup SHALL show a message instead of a translation when nothing is selected, when the client does not report a selection, when the English → Simplified Chinese model is not downloaded, or when the system is older than macOS 26.

#### Scenario: Model not downloaded
- **WHEN** the translation model is not installed
- **THEN** the popup SHALL tell the user to download English and Simplified Chinese under System Settings › General › Language & Region › Translation Languages

#### Scenario: Nothing selected
- **WHEN** the user presses `⌃⌥T` with an empty selection
- **THEN** the popup SHALL say that no text is selected
