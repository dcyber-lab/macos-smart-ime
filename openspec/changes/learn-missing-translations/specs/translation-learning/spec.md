## ADDED Requirements

### Requirement: Counting Words Without a Translation
In Chinese mode, the input method SHALL count a Space or number-key commit whose text:
- is 2–6 Han characters,
- has no translation in the user file or the built-in table, and
- has not been translated before.

It SHALL NOT count other commits. Counts SHALL decay with a 30-day half-life, and SHALL be stored only in `~/Library/Application Support/SmartIMEHost/translation-misses.json`.

#### Scenario: Word without a translation
- **WHEN** the user commits 灰度环境 with Space and no translation exists
- **THEN** 灰度环境 SHALL be counted once

#### Scenario: Word with a translation
- **WHEN** the user commits 数据库
- **THEN** nothing SHALL be recorded

#### Scenario: Not a word
- **WHEN** the user commits 我, raw letters with Return, or text with punctuation
- **THEN** nothing SHALL be recorded

### Requirement: Learning Missing Translations
When an input controller activates and at least the configured interval (default one day) has passed since the last run, the input method SHALL translate, in the background and on-device, up to 50 counted words that have at least 3 commits, most used first. For each word, it SHALL keep the English only if:
- it is 1–4 plain English words, and
- translating it back to Chinese gives the same word.

Each word SHALL be translated at most once.

#### Scenario: Learned
- **WHEN** 灰度环境 has 3 commits, a day has passed, and the translation round trip gives back 灰度环境
- **THEN** its English SHALL be added to the user translation file, and typing 灰度环境 SHALL show it as a translation candidate

#### Scenario: Rejected
- **WHEN** the round trip gives a different word, or the English is longer than four words
- **THEN** nothing SHALL be added, and the word SHALL NOT be translated again

#### Scenario: Languages not installed
- **WHEN** the Chinese and English translation languages are not installed
- **THEN** nothing SHALL be translated, and the next check SHALL happen within an hour

### Requirement: User Translation File
`~/Library/Application Support/SmartIMEHost/user-translations.tsv` SHALL hold `chinese<TAB>english[<TAB>english]` lines, with `#` for comments. Its lines SHALL take precedence over the built-in table. The file SHALL be reloaded when an input controller activates after it changed. Learned translations SHALL be appended to it.

#### Scenario: User line
- **WHEN** the user adds `内核<TAB>kernel` and switches to another app and back
- **THEN** typing 内核 SHALL show only "kernel" as its translation

#### Scenario: Deleting a learned line
- **WHEN** the user deletes a learned line
- **THEN** that word SHALL have no translation again and SHALL NOT be learned again

### Requirement: Translation Learning Settings
`TranslationLearningEnabled` (default true) SHALL turn counting and learning on or off. `TranslationLearningInterval` SHALL set the seconds between runs (default 86,400, minimum 60). Both SHALL be read from the input method's defaults domain on every use.

#### Scenario: Turned off
- **WHEN** `TranslationLearningEnabled` is false
- **THEN** no commit SHALL be counted and no translation SHALL run
