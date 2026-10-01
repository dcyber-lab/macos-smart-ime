## Context

`EnglishAugmentedChineseEngine` shows up to two translations of librime's first candidate, from the bundled `zh-en.tsv`. It records Chinese picks in `CandidateHistory`, but only as a count per typed input, never the Chinese text. Selection translation already calls Apple's on-device Translation framework from the input method process (`TranslationSession(installedSource:target:)`, macOS 26). The Companion app does not exist yet, so the input method process is the only place a background task can run.

## Goals / Non-Goals

**Goals:**
- A word the user commits often, and that has no translation, gets one without a release.
- Wrong learned translations stay rare.
- The per-keystroke cost stays negligible, and nothing leaves the machine.
- The user can see, edit, and delete what was learned.

**Non-Goals:**
- Correcting translations that exist but are wrong: that stays with the supplement or a user line.
- Cloud translation or an LLM.
- Sharing learned translations between users or folding them into the bundled table automatically.
- A settings UI.

## Decisions

### 1. Count misses in the engine, not from librime's user dictionary
librime's `userdb` already counts every commit, but exporting it goes through the levers API. That API opens the same LevelDB the running sessions hold; librime's own sync first closes every session. The engine instead sees each commit and whether it had a translation, so it records only the words that matter.
- Counted: a Space or number-key/click commit in Chinese mode whose text is 2–6 Han characters, has no user or bundled translation, and was not processed before.
- Not counted: Return (raw letters), commits with punctuation, single characters, longer phrases.

### 2. `TranslationMisses` store (`UserData`)
`translation-misses.json` holds:
- `words`: word → decayed usage. This is the same `Usage` as `CandidateHistory` (30-day half-life), moved to its own file.
- `processed`: word → when it was translated, kept or not.
- `lastRun`: when the task last finished.

It follows `CandidateHistory` in every other respect:
- `NSLock` around the in-memory state.
- Writes at most once per 2 seconds on a utility queue, atomically.
- An unreadable file starts empty.

Bounds are 2,000 words and 5,000 processed; the lowest-scoring or oldest tenth is dropped. Recording checks an `isEnabled` closure, so switching the setting off stops recording immediately.

### 3. `UserTranslations` overlay (`EnglishEngine`)
`user-translations.tsv` uses the supplement's format: `chinese<TAB>english[<TAB>english]`, with `#` comment lines. It is loaded once, and reloaded when an input controller activates if its modification date changed.
- The engine looks up a word here before the bundled table, so a user line also overrides a wrong built-in translation.
- Learned lines are appended to the end, under a `# Learned automatically` comment written once. A new file starts with a short header explaining the format.
- The in-memory copy updates immediately, and the file is written with an atomic replace.

### 4. When the learner runs
`IMEInputController.activateServer` calls `TranslationLearner.runIfDue()` (main actor). It starts one background task when all of these hold:
- learning is enabled
- at least `TranslationLearningInterval` has passed since `lastRun` (default 86,400 s, minimum 60 s)
- no run is in progress
- some word has at least 3 recorded commits

If the translation languages are not installed, it checks again at most once an hour and does not update `lastRun`. That way, installing the languages takes effect the same day.

### 5. What is kept
For each candidate, highest score first and at most 50 per run:
1. Skip the word if it gained a translation since it was recorded; it is dropped from `words`.
2. Translate zh-Hans → en, then translate the result en → zh-Hans.
3. Keep the English only if all of these hold:
   - it is 1–4 words
   - it uses only ASCII letters, digits, spaces, hyphens, and apostrophes, after trimming and dropping a trailing period
   - the round trip equals the word, ignoring whitespace
4. Fix the case: a lexicon word takes the lexicon's display form, and a sentence-cased result ("Kernel space") is lowercased when its first word is a lowercase lexicon word. Other capitalization is kept ("Zhang Wei", "ByteDance").
5. Mark the word processed either way, and log how many translations were kept and rejected.

A strict round trip rejects some good translations (a synonym comes back). It is chosen because a missing translation costs less than a wrong one.

### 6. Translator seam
`TermTranslator` is a protocol with `translate(_ word:) async throws -> (english, roundTrip)?`; `nil` means the languages are not installed. The production `AppleTermTranslator` reuses `LanguageAvailability` and `TranslationSession` as `AppleSelectionTranslator` does. Tests use a fake.

### 7. Settings
`TranslationLearningSettings` reads `TranslationLearningEnabled` (Bool, default true) and `TranslationLearningInterval` (seconds) from the input method's defaults domain on every use, like `SelectionTranslationSettings`.

## Risks / Trade-offs

- [Private words (names, internal code names) are stored and translated] → Only words without a translation, 2–6 characters, local files, bounded and decaying. One setting turns it off, and deleting the two files resets it. macOS keeps third-party input methods out of secure text fields.
- [A plausible but wrong translation passes the round trip] → It only fills words that had no translation, it appears after the Chinese candidates, and the user can delete the line.
- [Round-trip quality is unmeasured] → This Mac has no translation languages installed. The acceptance rate is checked in a real client after the languages are downloaded.
- [Delay: a word needs three commits and then the next daily run] → The bundled supplement still covers common terms. The interval setting shortens the wait.
- [Background work in the input method process] → The task is asynchronous, at most once a day, and off the key path. Keystrokes only take an in-memory lookup and, on a qualifying commit, a counter update.
