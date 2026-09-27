## ADDED Requirements

### Requirement: Word Completion Candidates
In English mode, the system SHALL provide word-level completion candidates based on the current sequence of typed characters.

#### Scenario: Show completion candidates
- **WHEN** the user types 'he' in English mode
- **THEN** the system SHALL display the typed text "he" as the first candidate, followed by completions like "her", "here", "help" in the candidate window

#### Scenario: Rank completions by frequency
- **WHEN** the typed text is a prefix of several words in the lexicon
- **THEN** completions SHALL be ordered from most to least frequent, excluding the typed text itself

#### Scenario: No completions available
- **WHEN** the typed text is not a prefix of any other word in the lexicon
- **THEN** the candidate window SHALL be hidden and the typed text SHALL remain as the composition

### Requirement: Bundled Completion Lexicon
The English engine SHALL complete from a bundled, frequency-ordered lexicon of at least 30,000 common English words that excludes profanity and slurs.

#### Scenario: Common and technical words are available
- **WHEN** the user types 'deplo' in English mode
- **THEN** "deployment" SHALL be among the completion candidates

#### Scenario: Offensive words are never suggested
- **WHEN** the typed text is a prefix of a word on the exclusion list
- **THEN** that word SHALL NOT appear as a completion candidate

### Requirement: Candidate Selection
The user MUST be able to select an English completion candidate using number keys or the `Space` key.

#### Scenario: Select first candidate with Space
- **WHEN** completion candidates are visible, no candidate is highlighted, and the user presses `Space`
- **THEN** the first candidate (the typed text) SHALL be committed to the client application followed by a space

#### Scenario: Select highlighted candidate with Space
- **WHEN** the user has highlighted a candidate with the arrow keys and presses `Space`
- **THEN** the highlighted candidate SHALL be committed to the client application followed by a space

#### Scenario: Select candidate with number key
- **WHEN** completion candidates are visible and the user presses '2'
- **THEN** the second candidate SHALL be committed to the client application
