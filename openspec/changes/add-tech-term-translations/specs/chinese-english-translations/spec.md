## ADDED Requirements

### Requirement: Layered Translation Table
The Chinese-to-English translation table SHALL be generated from, in order of precedence:
1. The project-authored supplement.
2. CC-CEDICT, with computing glosses first.
3. ECDICT `[计]` senses, for headwords the first two lack.

A headword SHALL take all of its translations from the highest layer that has it, and SHALL have at most two translations.

#### Scenario: Supplement term
- **WHEN** the user types `neihekongj` and the first Chinese candidate is 内核空间
- **THEN** "kernel space" SHALL appear as a translation candidate

#### Scenario: Computing gloss first
- **WHEN** the first Chinese candidate is 内核, which is not in the supplement
- **THEN** the translations SHALL be "kernel" then "core"

#### Scenario: ECDICT gap fill
- **WHEN** the first Chinese candidate is 源文件, which is in neither the supplement nor CC-CEDICT
- **THEN** the translation SHALL be "source file"

#### Scenario: Everyday word unchanged
- **WHEN** the first Chinese candidate is 问题 or 开心
- **THEN** the translations SHALL be the same as CC-CEDICT's first glosses ("question", "problem"; "feel happy", "rejoice")

### Requirement: Developer Term Coverage
The supplement SHALL cover common developer terms across operating systems, concurrency, data structures, languages and compilers, databases, networking, cloud and DevOps, security, version control, frontend and backend, testing, observability, and AI/ML. Where a term also has a common everyday meaning, that meaning SHALL be kept as the second translation.

#### Scenario: Technical sense first
- **WHEN** the first Chinese candidate is 仓库
- **THEN** the translations SHALL be "repository" then "warehouse"

### Requirement: Supplement Validation
The build SHALL fail when a supplement line:
- has a headword shorter than two Han characters,
- repeats a headword,
- has more than two translations, or
- has an empty field.

#### Scenario: Duplicate headword
- **WHEN** the supplement lists 容器 twice
- **THEN** `build-translations.py` SHALL exit with an error naming 容器

### Requirement: No GPL-Derived Content
Generating the translation table SHALL NOT read rime-ice or any other GPL-licensed data.

#### Scenario: Build inputs
- **WHEN** `build-translations.py` runs
- **THEN** its only inputs SHALL be CC-CEDICT, the pinned ECDICT, `wordlist.txt`, and the supplement
