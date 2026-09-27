## ADDED Requirements

### Requirement: English Candidates in Chinese Mode
While in Chinese mode, the system SHALL offer English word candidates from the bundled English lexicon alongside the `librime` candidates, without requiring a switch to English mode.

#### Scenario: English word typed in Chinese mode
- **WHEN** the user types `deploy` in Chinese mode
- **THEN** the candidate window SHALL include "deploy" together with the `librime` candidates

#### Scenario: Prefix completion in Chinese mode
- **WHEN** the user types `gith` in Chinese mode
- **THEN** the candidate window SHALL include "github" after the `librime` candidates

#### Scenario: No English match
- **WHEN** the user types `nihao` in Chinese mode
- **THEN** the candidate window SHALL show only the `librime` candidates

### Requirement: English Candidate Eligibility
The system SHALL compute English candidates in Chinese mode only when the raw input has at least three characters, consists only of lowercase letters `a`–`z`, and the first candidate page is shown. The system SHALL show at most three English candidates.

#### Scenario: Short input
- **WHEN** the user types `zg` in Chinese mode
- **THEN** no English candidates SHALL be shown

#### Scenario: Input with a syllable delimiter
- **WHEN** the raw input contains `'`
- **THEN** no English candidates SHALL be shown

#### Scenario: Later candidate page
- **WHEN** English candidates are shown and the user pages to the next candidate page
- **THEN** no English candidates SHALL be shown on that page

#### Scenario: Candidate cap
- **WHEN** more than three English words match the raw input
- **THEN** only the exact match, if any, and the most frequent completions SHALL be shown, up to three English candidates in total

### Requirement: English Candidate Placement
The system SHALL place an exact English word match before the `librime` candidates only when the raw input cannot be fully segmented into valid pinyin syllables. In every other case, English candidates SHALL follow the `librime` candidates.

#### Scenario: Non-pinyin English word goes first
- **WHEN** the user types `hello` in Chinese mode
- **THEN** "hello" SHALL be the first candidate

#### Scenario: Pinyin input keeps Chinese first
- **WHEN** the user types `women` in Chinese mode
- **THEN** the first candidate SHALL be the first `librime` candidate and "women" SHALL appear after all `librime` candidates on the page

### Requirement: English Candidate Selection
Selecting an English candidate SHALL commit the English word without a trailing space and clear the `librime` composition. Selecting a Chinese candidate SHALL behave exactly as it does without English candidates.

#### Scenario: Space commits a first-place English word
- **WHEN** the user types `hello` in Chinese mode and presses `Space`
- **THEN** "hello" SHALL be committed and the composition SHALL be cleared

#### Scenario: Space commits a first-place Chinese candidate
- **WHEN** the user types `women` in Chinese mode and presses `Space`
- **THEN** the first `librime` candidate SHALL be committed

#### Scenario: Number key selects an English candidate
- **WHEN** English candidates are shown and the user presses the number key of an English candidate
- **THEN** that English word SHALL be committed and the composition SHALL be cleared

#### Scenario: Number key selects a Chinese candidate after English candidates
- **WHEN** an English candidate is first and the user presses the number key of the first `librime` candidate
- **THEN** the first `librime` candidate on the current page SHALL be committed

#### Scenario: Highlighted English candidate committed with Space
- **WHEN** the user highlights an English candidate with the arrow keys and presses `Space`
- **THEN** that English word SHALL be committed

#### Scenario: Return commits raw input
- **WHEN** English candidates are shown and the user presses `Return`
- **THEN** the raw input SHALL be committed as `librime` does today
