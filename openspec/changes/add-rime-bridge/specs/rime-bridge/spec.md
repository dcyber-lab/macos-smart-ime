## ADDED Requirements

### Requirement: IME host can delegate Chinese composition to a `librime` bridge

The system SHALL provide a project-owned `rime-bridge` capability that the IME host can use for Chinese composition instead of placeholder session logic.

#### Scenario: Host forwards supported Chinese input to the bridge

- **WHEN** the active IME host receives supported key input while using the Chinese path
- **THEN** the host SHALL delegate the event to the `rime-bridge` session instead of generating placeholder candidates locally

### Requirement: `rime-bridge` manages the minimum `librime` runtime lifecycle

The system SHALL initialize `librime`, create a usable input session, and release bridge-owned resources when the session ends.

#### Scenario: Bridge prepares a usable session

- **WHEN** the host starts or resets a Chinese input session
- **THEN** the `rime-bridge` SHALL provide a live `librime` session that can process subsequent key events

### Requirement: `rime-bridge` returns project-owned session updates

The system SHALL convert raw `librime` context and commit data into project-owned models used by the host.

#### Scenario: Composition and candidates are exposed through host models

- **WHEN** `librime` returns updated composition and menu state for a processed key event
- **THEN** the `rime-bridge` SHALL surface composition text and candidate items using the project-owned shared session models

#### Scenario: Commit text is surfaced without exposing raw C structs

- **WHEN** `librime` emits committed text for a processed key event
- **THEN** the `rime-bridge` SHALL return that commit as a host-consumable update without leaking raw `RimeCommit` memory management into `IMEHostCore`

### Requirement: Host documentation covers local bridge validation assumptions

The system SHALL document the local `librime` dependency path required to build and validate the first bridge milestone.

#### Scenario: Local developer setup is explicit

- **WHEN** a developer follows the repository instructions for the `rime-bridge` milestone
- **THEN** the repository SHALL describe how the local `librime` installation is expected to be provided for build and validation
