## ADDED Requirements

### Requirement: Repository provides a repeatable IME install workflow

The system SHALL provide a repository-owned workflow for building and installing the current `SmartIMEHost` app as a macOS input method.

#### Scenario: Deterministic local build output is produced

- **WHEN** a developer runs the documented local build workflow
- **THEN** the repository SHALL produce a `SmartIMEHost.app` bundle at a deterministic local output path suitable for installation

#### Scenario: Installed app is copied to a real input methods directory

- **WHEN** a developer runs the documented local install workflow
- **THEN** the workflow SHALL place the built `SmartIMEHost.app` into either `~/Library/Input Methods/` or `/Library/Input Methods/`

### Requirement: Repository documents a manual validation checklist

The system SHALL document how to enable and manually validate the installed input method in macOS.

#### Scenario: Developer can follow one validation path

- **WHEN** a developer reads the repository validation document
- **THEN** the repository SHALL describe the prerequisites, install steps, enablement steps, and expected validation outcomes for the current IME host

### Requirement: Current Chinese input path can be checked in a real text client

The system SHALL define a basic manual validation loop for the currently implemented Chinese input behavior.

#### Scenario: Basic Chinese composition can be validated

- **WHEN** the installed input method is enabled in macOS and used in a normal text field
- **THEN** the validation checklist SHALL include a basic pinyin input and commit check against the current `librime` bridge path
