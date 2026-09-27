## ADDED Requirements

### Requirement: Translation While Pinyin Is Incomplete
In Chinese mode, the system SHALL offer translations of the first `librime` candidate whenever that candidate has two or more characters and no exact English word is placed first, regardless of whether the raw input is complete pinyin.

#### Scenario: Unfinished pinyin
- **WHEN** the user types `shujuk` and the first `librime` candidate is 数据库
- **THEN** "database" SHALL appear among the candidates

#### Scenario: Abbreviated pinyin
- **WHEN** the user types `sjk` and the first `librime` candidate is 数据库
- **THEN** "database" SHALL appear among the candidates

#### Scenario: English word placed first
- **WHEN** the user types `hello` and "hello" is placed first
- **THEN** no translation candidates SHALL be shown

### Requirement: English Completion Promotion
When the raw input has at least four letters, cannot be fully segmented into pinyin syllables, and has at least one English completion, the most frequent English completion SHALL be placed second, directly after the first `librime` candidate. The first candidate SHALL stay the first `librime` candidate.

#### Scenario: Non-pinyin prefix
- **WHEN** the user types `gith` in Chinese mode
- **THEN** the second candidate SHALL be "GitHub" and `Space` SHALL still commit the first Chinese candidate

#### Scenario: Short input is not promoted
- **WHEN** the user types `dep` in Chinese mode
- **THEN** English completions SHALL stay after the `librime` candidates

#### Scenario: Complete pinyin is not promoted
- **WHEN** the user types `wome` or `women` in Chinese mode
- **THEN** English completions SHALL stay after the `librime` candidates

### Requirement: Rare Words in Chinese Mode
In Chinese mode, English candidates SHALL come from common words (the 30,000 most frequent) and the supplement. Rarer words SHALL only be offered when the input has at least five letters and cannot be fully segmented into pinyin. Only common words and supplement terms SHALL be placed first or promoted to position 2.

#### Scenario: Rare word matching a pinyin abbreviation
- **WHEN** the user types `dep` and "dep" is a rare word
- **THEN** "dep" SHALL NOT be placed first and the first candidate SHALL be the first `librime` candidate

#### Scenario: Rare names from unfinished pinyin
- **WHEN** the user types `shuj` and only rare words such as "shuji" start with it
- **THEN** no English word candidates SHALL be shown

#### Scenario: Long non-pinyin input
- **WHEN** the user types five or more letters that cannot be pinyin and a rare word starts with them
- **THEN** the rare word MAY be offered after the `librime` candidates

