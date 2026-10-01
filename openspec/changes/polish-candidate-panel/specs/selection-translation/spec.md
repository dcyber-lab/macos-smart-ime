## ADDED Requirements

### Requirement: Popup Layout
The translation popup SHALL show, top to bottom: a capsule badge with the direction (英 → 中 or 中 → 英, or 翻译 for messages) followed by the source text on one line, the translation or message wrapping at 400 pt, and the key hint. The popup SHALL keep the same inset between its content and every edge.

#### Scenario: Long source line
- **WHEN** the source text is "please review the plan before Friday"
- **THEN** the source line SHALL end at least the right inset away from the popup's right edge

#### Scenario: Message
- **WHEN** the translation model is not installed
- **THEN** the badge SHALL read 翻译, no source text SHALL be shown, and the message SHALL wrap inside the insets
