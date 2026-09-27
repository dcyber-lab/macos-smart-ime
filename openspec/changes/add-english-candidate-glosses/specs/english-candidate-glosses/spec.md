## ADDED Requirements

### Requirement: Chinese Gloss for English Candidates
English word candidates SHALL show a short Chinese gloss after the word, in both Chinese mode and English mode, when the glossary has an entry. Translation candidates SHALL NOT show a gloss.

#### Scenario: English word in Chinese mode
- **WHEN** the user types `deploy` in Chinese mode
- **THEN** the "deploy" candidate SHALL show the gloss 部署

#### Scenario: English mode completions
- **WHEN** the user types `meet` in English mode
- **THEN** the "meeting" candidate SHALL show a gloss such as 会议

#### Scenario: Translation candidate
- **WHEN** the user types `shujuku` and "database" appears as a translation
- **THEN** the "database" candidate SHALL NOT show a gloss

#### Scenario: Word without an entry
- **WHEN** an English candidate has no glossary entry
- **THEN** the candidate SHALL be shown without a gloss

### Requirement: Gloss Quality
Glosses SHALL use the most common part of speech (the part-of-speech line with the most senses in ECDICT) and at most two short senses. Supplement terms SHALL use their hand-written workplace gloss.

#### Scenario: Most frequent part of speech
- **WHEN** the gloss for "good" is shown
- **THEN** it SHALL be an adjective sense such as 好的

#### Scenario: Workplace term
- **WHEN** the gloss for "GitHub", "iOS", or "roadmap" is shown
- **THEN** it SHALL be the supplement's hand-written gloss

### Requirement: Gloss Display
The panel SHALL draw the gloss after the candidate text in smaller secondary text, truncated to 12 characters, and SHALL size the panel to include it.

#### Scenario: Long gloss
- **WHEN** a gloss is longer than 12 characters
- **THEN** the panel SHALL show its first 12 characters followed by an ellipsis
