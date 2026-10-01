## ADDED Requirements

### Requirement: Learned English Completions
English word completions SHALL list lexicon words the user has committed before, most used first (recent use counting more), ahead of words ranked by corpus frequency. In English mode the typed text SHALL remain the first candidate.

#### Scenario: English mode
- **WHEN** the user has committed "deployment" several times and types `dep` in English mode
- **THEN** the candidates SHALL be "dep", then "deployment", then other completions by frequency

#### Scenario: Chinese mode completions
- **WHEN** the user has committed "deployment" and types `deplo` in Chinese mode
- **THEN** "deployment" SHALL come before "deployed" among the English word candidates

### Requirement: Learned Choice Per Input
In Chinese mode, an English candidate the user picked before for the same input SHALL appear directly after the first Chinese candidate. It SHALL become the first candidate when it has been picked more often than Chinese for that input, and, for input that reads as pinyin, at least twice.

#### Scenario: Non-pinyin input
- **WHEN** the user picked "GitHub" for `gith` once
- **THEN** typing `gith` SHALL show "GitHub" first and Space SHALL commit it

#### Scenario: Pinyin input, one pick
- **WHEN** the user picked "database" for `shujuku` once
- **THEN** "database" SHALL appear second and Space SHALL still commit 数据库

#### Scenario: Pinyin input, two picks
- **WHEN** the user picked "database" for `shujuku` twice and never picked Chinese for it
- **THEN** "database" SHALL appear first

#### Scenario: Chinese taken back
- **WHEN** an English candidate leads for an input and the user picks Chinese for that input more often than that candidate
- **THEN** the first Chinese candidate SHALL lead again

### Requirement: Chinese Preference Over a Leading English Word
A common non-pinyin English word that would lead SHALL move to directly after the first Chinese candidate when the user has picked Chinese for that input more often than the word.

#### Scenario: Picking Chinese for an English word
- **WHEN** the user types `hello` and picks 何乐
- **THEN** typing `hello` again SHALL show 何乐 first and "hello" second

### Requirement: Recording Scope
The input method SHALL record only lexicon words and, for compositions of three or more letters, which English candidate or Chinese was picked. It SHALL NOT record Chinese text, words outside the lexicon, or raw input committed with Return. A Chinese pick SHALL be recorded only for inputs with English picks on record or with an English candidate in first place.

#### Scenario: Ordinary Chinese typing
- **WHEN** the user types `women` and commits 我们 with no English pick on record
- **THEN** nothing SHALL be recorded for `women`

#### Scenario: Unknown word
- **WHEN** the user commits a word not in the lexicon in English mode
- **THEN** it SHALL NOT be recorded

### Requirement: Local Bounded Storage
The record SHALL be stored only in `~/Library/Application Support/SmartIMEHost/candidate-history.json`, loaded once per process, written in the background at most every 2 seconds, and bounded to 5,000 words and 2,000 inputs. An unreadable file SHALL be treated as empty.

#### Scenario: Reset
- **WHEN** the user deletes the file and the input method restarts
- **THEN** candidates SHALL follow the built-in order again

#### Scenario: Corrupt file
- **WHEN** the file is not valid JSON
- **THEN** the input method SHALL start with an empty record and keep working
