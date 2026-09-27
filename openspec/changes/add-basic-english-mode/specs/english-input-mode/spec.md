## ADDED Requirements

### Requirement: Toggle English Mode
The system MUST allow the user to toggle between Chinese and English input modes using a single `Shift` key press.

#### Scenario: Toggle to English from Chinese
- **WHEN** the current mode is Chinese and the user presses and releases the `Shift` key without other keys
- **THEN** the system mode SHALL change to English

#### Scenario: Toggle back to Chinese from English
- **WHEN** the current mode is English and the user presses and releases the `Shift` key without other keys
- **THEN** the system mode SHALL change to Chinese

### Requirement: English Character Pass-through
In English mode, characters that are not part of a completion (like punctuation) MUST be committed directly to the focused application.

#### Scenario: Commit non-word characters
- **WHEN** in English mode and the user types '.'
- **THEN** '.' SHALL be immediately committed to the client application
