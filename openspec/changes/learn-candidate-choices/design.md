## Context

`EnglishAugmentedChineseEngine` merges English words and translations into librime's first page by fixed rules (exact non-pinyin word first, 4+ letter non-pinyin completion at position 2, everything else after the Chinese candidates). `BasicEnglishEngine` lists the typed text and then `EnglishLexicon` completions by wordfreq rank. Neither remembers anything. librime keeps its own user dictionary for Chinese words and already ranks them by the user's decayed commit counts.

## Goals / Non-Goals

**Goals:**
- The user's usual English choice for an input rises to the position they reach fastest, and to Space once it clearly beats Chinese.
- English completions follow the user's vocabulary before corpus frequency.
- No measurable per-keystroke cost; nothing leaves the machine.

**Non-Goals:**
- Changing Chinese candidate order (librime's user dictionary does that).
- Learning words that are not in the lexicon (names, identifiers, anything that could be a secret).
- A settings UI, sync between machines, or import/export.

## Decisions

### 1. Two records in one store
`CandidateHistory` (package `UserData`) keeps:
- `words`: lexicon key (`github`) → usage. Recorded for every English word committed in either mode when the lexicon contains it.
- `inputs`: raw input (`gith`, `shujuku`) → usage of Chinese (one aggregate, no Chinese text) and of each English candidate text.

A usage is `count`, `weight`, `lastUsed`. Its score is `weight × 0.5^(age / 30 days)`; recording sets `weight = score + 1`. Frequent and recent picks both count, and old habits fade. Counts stay exact for thresholds.

Alternative considered: feeding English picks into librime's user dictionary. librime has no entry point for words it did not produce, and English words are not pinyin codes.

### 2. What is recorded in Chinese mode
- English commit (number key, click, or Space on a leading English candidate): the input's English usage for that text, plus the word record.
- Chinese commit: the input's Chinese usage, only when the input already has English picks or an English candidate was first. Chinese choices elsewhere are librime's business, and this keeps the file small.
- Return (commits the raw letters) and inputs shorter than three letters are not recorded.

### 3. Ranking in Chinese mode
Order: `[first] + chinese[0] + [second] + chinese[1...] + translations + words`, deduplicated, at most nine.
- Picks are English texts recorded for this input that are still valid candidates: a translation of the current first Chinese candidate, or a usable lexicon word completing the input. Highest score first.
- `first` is the top pick when its score beats the Chinese score and, for pinyin input, it was picked at least twice; otherwise the exact common non-pinyin word, unless Chinese outscores it for this input.
- `second` holds at most two of: the other picks, the exact word when it does not lead, the existing promoted completion (4+ letter non-pinyin). Capping it keeps all five Chinese candidates on the page.
- Word completions come from `EnglishLexicon.completions(forPrefix:limit:preferring:)`: learned words with the prefix first (score order), then corpus order.

Pinyin needs two picks because a single accidental pick of `database` for `shujuku` must not make Space type English.

### 4. Ranking in English mode
Candidates stay `[typed text] + completions`; completions use the same learned-first helper. Space still commits the typed text.

### 5. Storage
- `~/Library/Application Support/SmartIMEHost/candidate-history.json`, JSON with short keys, `version: 1`.
- Loaded once per process when the first input controller is created; an unreadable or unknown-version file starts empty and is overwritten on the next save.
- Changes are written at most once per 2 seconds on a utility queue from a copy taken under the lock, with an atomic write.
- Bounded: 5,000 words and 2,000 inputs; past that the lowest-scoring 10% are dropped.
- `NSLock` guards the in-memory state, so the store is `Sendable` and engines stay synchronous.

## Risks / Trade-offs

- [One pick moves an English word to Space for non-pinyin input] → Non-pinyin input rarely means Chinese (`gith` → 个); pinyin input needs two picks, and picking Chinese once more takes it back.
- [Typed English words are stored] → Only lexicon words, local only, file documented; deleting it resets learning.
- [Linear prefix scan over up to 5,000 learned words per keystroke] → Tens of microseconds; the store is bounded.
- [Lost learning on crash] → At most the last 2 seconds.
