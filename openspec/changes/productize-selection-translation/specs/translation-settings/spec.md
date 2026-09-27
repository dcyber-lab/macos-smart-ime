## ADDED Requirements

### Requirement: Enable Setting
The feature SHALL be on by default and SHALL be turned off when `SelectionTranslationEnabled` is false in the input method's defaults domain, without restarting the input method.

#### Scenario: Disabled
- **WHEN** `SelectionTranslationEnabled` is false and the user presses the hotkey
- **THEN** no translation SHALL start and the key SHALL reach the application

### Requirement: Hotkey Setting
The hotkey SHALL default to `ctrl+option+t` and SHALL be configurable with `SelectionTranslationHotkey` as modifiers plus one letter. Values without ctrl, option, or cmd, or otherwise invalid, SHALL fall back to the default.

#### Scenario: Custom hotkey
- **WHEN** `SelectionTranslationHotkey` is `cmd+shift+y`
- **THEN** `⌘⇧Y` SHALL start a translation and `⌃⌥T` SHALL not

#### Scenario: Invalid hotkey
- **WHEN** `SelectionTranslationHotkey` is `shift+t` or `ctrl+option+tt`
- **THEN** the hotkey SHALL be `⌃⌥T`
