## Why

The built-in translation table cannot cover every user's own vocabulary: team jargon, product names, and newer terms. Every missing word needs a hand-written supplement entry and a new release. The input method already sees which Chinese words the user commits often. It can translate those that have no English on-device, and offer the translation the next time.

## What Changes

- In Chinese mode, a Space or number-key commit of a 2–6 character Chinese word that has no translation is counted in `translation-misses.json`. Counts decay with a 30-day half-life, and the file is bounded.
- Once a day, when an input controller activates, a background task picks up to 50 words committed at least 3 times.
  - It translates them with Apple's on-device Translation framework (the same one selection translation uses), then translates the English back.
  - It keeps a translation only if it is 1–4 plain English words and the round trip gives back the same Chinese word.
- Kept translations are appended to `user-translations.tsv`. This is a plain, user-editable file of `chinese<TAB>english` lines that overrides the built-in table. The user can also add lines of their own.
- The file is reloaded when an input controller activates, so edits apply without restarting.
- A word is translated at most once, whether kept or not. Deleting a learned line removes it for good.
- `TranslationLearningEnabled` (default on) turns off both recording and translating. `TranslationLearningInterval` (default one day) sets how often the task runs.
- Nothing leaves the machine. Without the Chinese and English translation languages installed, the task does nothing.

## Capabilities

### New Capabilities
- `translation-learning`: which commits are counted, when and how missing translations are learned, the user translation file, and settings.

### Modified Capabilities
- `candidate-learning`: its recording scope ("no Chinese text") now covers `candidate-history.json` only. Chinese words without a translation are recorded by `translation-learning`.

## Impact

- `packages/user-data`: new `TranslationMisses` store (the shared decayed `Usage` moves to its own file).
- `packages/english-engine`: new `UserTranslations` overlay. `EnglishAugmentedChineseEngine` looks it up first and records misses.
- `apps/ime/Sources/IMEHostCore`:
  - new `TranslationLearner`, `AppleTermTranslator`, and `TranslationLearningSettings`
  - `IMEInputController` shares the stores and runs the learner on activation
  - new file URLs in `IMEHostConfiguration`
- Privacy: Chinese words the user commits are now stored when they have no translation. They stay local, bounded, and deletable, and can be switched off.
