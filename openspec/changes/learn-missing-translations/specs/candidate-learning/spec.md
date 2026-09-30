## MODIFIED Requirements

### Requirement: Recording Scope
`candidate-history.json` SHALL hold only:
- lexicon words, and
- for compositions of three or more letters, which English candidate or Chinese was picked.

It SHALL NOT hold Chinese text, words outside the lexicon, or raw input committed with Return. A Chinese pick SHALL be recorded only for inputs with English picks on record or with an English candidate in first place. Chinese words without a translation are recorded separately, as the `translation-learning` capability specifies.

#### Scenario: Ordinary Chinese typing
- **WHEN** the user types `women` and commits 我们 with no English pick on record
- **THEN** nothing SHALL be recorded for `women` in `candidate-history.json`

#### Scenario: Unknown word
- **WHEN** the user commits a word not in the lexicon in English mode
- **THEN** it SHALL NOT be recorded
