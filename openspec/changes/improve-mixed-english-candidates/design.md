## Context

`EnglishAugmentedChineseEngine` merges English words (`EnglishLexicon`) and CC-CEDICT translations of the first `librime` candidate into the Chinese list. Measured with real librime on the repository data:

```
shuj     1.数据 2.暑假 …                 (no translation)
shujuk   1.数据库 2.数据卡 …             (no translation)
sjk      1.数据库 2.手机卡 …             (no translation)
shujuku  1.数据库 … 6.database[译]
featu    1.反而阿土 2.反而 … 6.features 7.feature
gith     1.个 2.给 … 6.github
kube / json / refac                      (no English at all)
```

Translations require the input to be fully segmentable into pinyin syllables, and prefix completions are always appended after the Rime page.

## Goals / Non-Goals

**Goals:**
- Offer translations as soon as the first Chinese candidate is a real word, however the pinyin was typed.
- Make English completions for obviously non-pinyin input reachable with one key press.
- Cover common technical and office vocabulary with correct casing.

**Non-Goals:**
- Putting English completions first in Chinese mode (Space would start committing English for half-typed pinyin).
- User-editable translation tables or learning (separate change).
- Changing English-mode candidate rules beyond the larger lexicon and display casing.

## Decisions

### 1. Translate whenever the first candidate is a multi-character word
Drop the "fully segmentable pinyin" condition for translations. Translate the first `librime` candidate when it has two or more characters and no exact English word was placed first. Nonsense multi-syllable guesses for English-like input (`反而阿土`) are not in CC-CEDICT, so they add no translation.

Alternative considered: accept pinyin with a partial last syllable only. Almost any letter string passes a "syllables or syllable prefixes" test, and abbreviations (`sjk`) would still be excluded, so the extra rule adds complexity without filtering much.

### 2. Promote one English completion to position 2
When the input has at least four letters, cannot be segmented into complete pinyin syllables, and has at least one English completion, the most frequent completion is placed directly after the first Chinese candidate. Other English candidates keep their existing places.

- Four letters: three-letter inputs such as `dep` are often pinyin abbreviations or unfinished syllables (得票); promoting `department` there would take over number key 2.
- Position 2, not 1: `Space` must keep committing Chinese for inputs that may still become pinyin.

### 3. Lexicon: 100,000 words plus a display-cased supplement
- `wordlist.txt` grows to 100,000 wordfreq words (same generator, `--size 100000`, same exclusion list). Measured coverage of 67 sampled tech/office terms: 30 at 30k, 56 at 100k.
- `supplement.txt` (project-authored, one display form per line, e.g. `GitHub`) covers the remaining workplace terms and brand casing.
- `EnglishLexicon` stores a lowercase key and a display form per entry. Lookups and prefix matching use the key; candidates use the display form. When a supplement key also exists in the word list, the supplement's display form and the better of the two ranks win.
- Supplement entries get rank `index + 2000`, so they sort after the most common English words but ahead of the long tail. This keeps `git` → `github` and `ty` → `typescript` visible without displacing `the` or `they`.

### 4. Keep the long tail out of pinyin typing
The 100,000-word list contains abbreviations and romanized names (`dep` rank 30,135; `shuji`, `shuja` above rank 94,000) that collide with pinyin. In Chinese mode, English candidates use common words (rank below 30,000, the previous list size) plus the supplement; rarer words appear only for 5+ letter input that cannot be pinyin. Only common words and supplement terms go first or get promoted. English mode keeps using the full list.

### 5. Performance
Loading 100,000 entries, sorting them, and building the key index happens once per process. Tests assert the bundled lexicon loads in under 1 second in debug builds; release builds are several times faster. Prefix lookups stay binary search plus a scan of matching words.

## Risks / Trade-offs

- [Translations of partial pinyin can be wrong when Rime's first guess is wrong] → They are appended after the Chinese candidates and never committed by `Space`.
- [Position 2 promotion changes what number key 2 selects for 4+ letter non-pinyin input] → Only when the input cannot be complete pinyin; complete pinyin (`women`, `change`) is unaffected.
- [A larger lexicon adds rare words to English completions] → Completions stay frequency ordered and capped; supplement terms rank ahead of the long tail.
- [Display casing may not match every user's preference (`json` vs `JSON`)] → The supplement lists one preferred form; the literal typed text is still available in English mode.
