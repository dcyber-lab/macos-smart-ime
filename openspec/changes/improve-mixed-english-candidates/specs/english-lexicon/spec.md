## ADDED Requirements

### Requirement: Lexicon Size and Supplement
The bundled English lexicon SHALL contain at least 100,000 frequency-ordered words plus a project-maintained supplement of technical and office terms.

#### Scenario: Technical terms are available
- **WHEN** the user types `refac`, `kube`, or `json`
- **THEN** "refactor", "Kubernetes", and "JSON" respectively SHALL be among the English completions

### Requirement: Display Casing
Lexicon matching SHALL be case-insensitive, and candidates SHALL use the supplement's display form when one exists.

#### Scenario: Brand casing
- **WHEN** the user types `github` or `ios`
- **THEN** the English candidate SHALL be "GitHub" or "iOS"

#### Scenario: Plain words stay lowercase
- **WHEN** the user types `hello`
- **THEN** the English candidate SHALL be "hello"

### Requirement: Supplement Ranking
Supplement terms SHALL rank after the most common English words but ahead of rare words in prefix completions.

#### Scenario: Supplement beats rare words
- **WHEN** the user types `typ` and both "typescript" and a rare word share the prefix
- **THEN** "TypeScript" SHALL rank ahead of the rare word

#### Scenario: Common words stay first
- **WHEN** the user types `th`
- **THEN** "the", "that", and "this" SHALL remain the top completions
