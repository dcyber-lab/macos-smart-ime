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

### Requirement: Translation Candidates in Chinese Mode
When the raw input is eligible and can be fully segmented into valid pinyin syllables, the system SHALL look up the first `librime` candidate in the bundled Chinese→English dictionary if it has two or more characters, and SHALL show up to two English translations directly after the `librime` candidates and before any appended English word candidates.

#### Scenario: Translation of a typed Chinese word
- **WHEN** the user types `shujuku` in Chinese mode and the first `librime` candidate is 数据库
- **THEN** "database" SHALL appear after the `librime` candidates

#### Scenario: Common-noun translation preferred over proper noun
- **WHEN** the first `librime` candidate is 苹果
- **THEN** the first translation SHALL be "apple"

#### Scenario: Single-character candidate
- **WHEN** the first `librime` candidate is a single character
- **THEN** no translation candidates SHALL be shown

#### Scenario: Non-pinyin input
- **WHEN** the user types `hello` in Chinese mode
- **THEN** no translation candidates SHALL be shown

#### Scenario: Word not in the dictionary
- **WHEN** the first `librime` candidate has no dictionary entry
- **THEN** only the `librime` candidates and any English word candidates SHALL be shown

### Requirement: Merged Candidate Limits
The merged candidate list SHALL contain at most nine entries so every entry has a selection key, and SHALL NOT contain the same text twice.

#### Scenario: Full page with translations and English words
- **WHEN** `librime` shows five candidates, two translations are available, and three English words match
- **THEN** the list SHALL contain the five `librime` candidates, the two translations, and the first two English words

#### Scenario: Translation equals an English word candidate
- **WHEN** a translation has the same text as an English word candidate
- **THEN** it SHALL appear only once, in the translation position

### Requirement: Preedit for Non-Pinyin Input
When the raw input consists only of lowercase letters, cannot be fully segmented into valid pinyin syllables, and no part of it has been converted to Chinese yet, the composition text shown in the client and in the panel SHALL be the raw input instead of the `librime` syllable segmentation.

#### Scenario: English word typed in Chinese mode
- **WHEN** the user types `good` in Chinese mode and `librime` segments it as "go o d"
- **THEN** the composition text SHALL be "good"

#### Scenario: Pinyin keeps the syllable segmentation
- **WHEN** the user types `shujuku` in Chinese mode
- **THEN** the composition text SHALL be the `librime` preedit, e.g. "shu ju ku"

#### Scenario: Partially converted input keeps the librime preedit
- **WHEN** part of a non-pinyin input has already been converted to Chinese characters
- **THEN** the composition text SHALL be the `librime` preedit

### Requirement: English Candidate Selection
Selecting an English candidate, whether an English word or a translation, SHALL commit the English text without a trailing space and clear the `librime` composition. Selecting a Chinese candidate SHALL behave exactly as it does without English candidates.

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

#### Scenario: Number key selects a translation
- **WHEN** the user types `shujuku` and presses the number key of "database"
- **THEN** "database" SHALL be committed and the composition SHALL be cleared

#### Scenario: Highlighted English candidate committed with Space
- **WHEN** the user highlights an English candidate with the arrow keys and presses `Space`
- **THEN** that English word SHALL be committed

#### Scenario: Return commits raw input
- **WHEN** English candidates are shown and the user presses `Return`
- **THEN** the raw input SHALL be committed as `librime` does today
