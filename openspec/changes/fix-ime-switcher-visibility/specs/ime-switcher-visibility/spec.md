## ADDED Requirements

### Requirement: `SmartIMEHost` exposes stable switcher-facing display metadata

The system SHALL provide explicit display metadata for `SmartIMEHost` so macOS can surface the input method in UI presentation contexts beyond System Settings.

#### Scenario: Bundle contains a stable display name and language metadata

- **WHEN** `SmartIMEHost` is built for installation
- **THEN** the bundle SHALL include a `CFBundleDisplayName`, localized display-name resources, and `tsInputMethodLanguageKey`

### Requirement: Installation repairs malformed HIToolbox keyboard-input-method entries

The system SHALL repair malformed `AppleEnabledInputSources` entries that would prevent a valid keyboard input method from appearing in the switcher.

#### Scenario: Invalid keyboard-input-method entry is removed

- **WHEN** the install workflow encounters an enabled-input-sources item with `InputSourceKind = Keyboard Input Method` and no `Bundle ID`
- **THEN** the workflow SHALL remove that malformed entry while preserving valid neighboring items

### Requirement: Installation ensures a single valid enabled `SmartIMEHost` source

The system SHALL ensure that the logged-in user ends the install workflow with exactly one valid enabled `SmartIMEHost` keyboard input method entry.

#### Scenario: Duplicate or missing `SmartIMEHost` entry is normalized

- **WHEN** the install workflow repairs the logged-in user's HIToolbox preferences
- **THEN** it SHALL remove duplicate `SmartIMEHost` entries and ensure a single valid keyboard-input-method entry remains in `AppleEnabledInputSources`

### Requirement: Switcher validation includes menu and cycling visibility

The system SHALL document validation outcomes in terms of both System Settings visibility and actual runtime switcher visibility.

#### Scenario: Validation checklist distinguishes UI surfaces

- **WHEN** a developer validates a freshly installed `SmartIMEHost`
- **THEN** the repository SHALL provide a checklist that explicitly covers menu bar visibility and keyboard shortcut cycling in addition to System Settings visibility
