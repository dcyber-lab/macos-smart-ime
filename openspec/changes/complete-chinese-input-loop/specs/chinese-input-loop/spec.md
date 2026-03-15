## ADDED Requirements

### Requirement: Chinese composition stays visible during active pinyin entry

The system SHALL keep the current Chinese composition visible in the active macOS text client while the user is entering a pinyin sequence that has not yet been committed.

#### Scenario: Active pinyin entry updates inline composition
- **WHEN** the user switches to `SmartIMEHost` and types a supported pinyin sequence such as `nihao`
- **THEN** the IME SHALL update the active composition in the focused client without inserting raw Latin characters as committed text

### Requirement: Chinese candidates are shown through a visible candidate panel

The system SHALL present the current `librime` candidate list in a visible candidate panel whenever an active Chinese composition has selectable candidates.

#### Scenario: Candidate panel appears for active composition
- **WHEN** the current Chinese composition contains one or more candidates
- **THEN** the IME SHALL show a visible candidate panel backed by the current candidate list

### Requirement: Candidate acceptance commits Chinese text and clears composition

The system SHALL commit the selected Chinese text into the focused client and clear the active composition after a final candidate selection.

#### Scenario: Space or number-key selection commits a candidate
- **WHEN** the user accepts a visible candidate through the current key-driven selection path
- **THEN** the IME SHALL insert the selected Chinese text into the client and clear the current composition and visible candidates

#### Scenario: Candidate panel final selection commits a candidate
- **WHEN** the candidate panel reports a final selected candidate
- **THEN** the IME SHALL insert that selected Chinese text into the client and clear the current composition and visible candidates

### Requirement: Escape cancels Chinese composition without leaking raw key input

The system SHALL cancel an active Chinese composition without committing text or leaking the raw cancel key into the client.

#### Scenario: Escape clears active composition
- **WHEN** the user presses `Escape` while a Chinese composition is active
- **THEN** the IME SHALL clear the composition, hide the candidate panel, and avoid inserting a literal escape-triggered character into the client

### Requirement: Chinese input loop requires real GUI validation

The system SHALL define completion of the milestone in terms of real macOS GUI validation, not only local build success.

#### Scenario: Manual validation covers visible candidates and commit
- **WHEN** a developer validates the Chinese input loop milestone
- **THEN** the repository SHALL provide a checklist that covers candidate visibility, candidate acceptance, committed Chinese output, and cancel behavior in a standard macOS text client
