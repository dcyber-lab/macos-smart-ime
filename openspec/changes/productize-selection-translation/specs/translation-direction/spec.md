## ADDED Requirements

### Requirement: Automatic Translation Direction
The system SHALL translate a selection from Simplified Chinese to English when it has at least one Han character and at least as many Han characters as English words, and any other selection from English to Simplified Chinese. The popup SHALL show the direction as 中 → 英 or 英 → 中.

#### Scenario: English selection
- **WHEN** the user translates "please review the plan"
- **THEN** it SHALL be translated English → Simplified Chinese and the popup SHALL show 英 → 中

#### Scenario: Chinese selection
- **WHEN** the user translates "请在周五前审阅部署计划"
- **THEN** it SHALL be translated Simplified Chinese → English and the popup SHALL show 中 → 英

#### Scenario: Chinese sentence with English terms
- **WHEN** the user translates "这个feature要deploy到production"
- **THEN** it SHALL be translated Simplified Chinese → English

#### Scenario: English sentence with a Chinese term
- **WHEN** the user translates "Let's discuss 数据库 design"
- **THEN** it SHALL be translated English → Simplified Chinese

#### Scenario: Missing model for the chosen direction
- **WHEN** the model for the chosen direction is not installed
- **THEN** the popup SHALL name that language pair and where to download it
