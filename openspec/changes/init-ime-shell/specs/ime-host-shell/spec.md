## ADDED Requirements

### Requirement: IME host target can be installed and enabled
The system SHALL provide a macOS IME host target that can be built, registered, and enabled as an input method for local validation.

#### Scenario: Host target is available to the system
- **WHEN** the project is built and the IME host is installed using the documented local workflow
- **THEN** macOS SHALL expose the input method as an available input source for activation

### Requirement: IME host manages a minimal input session
The system SHALL create and maintain a minimal input session that tracks composition text and candidate state for the active client.

#### Scenario: Composition state updates from input
- **WHEN** the active IME host receives supported key input in a text client
- **THEN** the session SHALL update composition state without requiring `librime` integration

#### Scenario: Candidate state is represented in the session
- **WHEN** the host updates composition state
- **THEN** the session SHALL expose a candidate collection, even if the first milestone uses placeholder candidate data

### Requirement: IME host can commit text to the focused client
The system SHALL support an end-to-end commit path from host input handling to text insertion in the focused client.

#### Scenario: Deterministic commit path works
- **WHEN** the host receives the configured test input sequence
- **THEN** the host SHALL commit deterministic text to the focused text client

### Requirement: IME host boundary remains engine-agnostic
The system SHALL keep host lifecycle and input-session handling separate from future engine implementations.

#### Scenario: Host does not depend on real engine logic
- **WHEN** the first milestone is implemented
- **THEN** the IME host SHALL function without requiring `librime`, English completion, or Companion integration
