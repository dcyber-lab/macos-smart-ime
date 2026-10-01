## ADDED Requirements

### Requirement: Panel Hides on Commit
When a commit plays an effect, the candidate panel SHALL fade out within 100 ms with the committed row already removed. Otherwise it SHALL hide at once. Showing the panel again SHALL cancel the fade.

#### Scenario: Next key during the fade
- **WHEN** the user commits 你好 and types `w` within 100 ms
- **THEN** the panel for `w` SHALL be fully visible
