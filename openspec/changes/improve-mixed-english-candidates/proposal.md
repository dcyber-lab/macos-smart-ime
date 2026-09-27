## Why

English help in Chinese mode only appears once the input is complete. Translations wait for fully typed pinyin (`shujuk` and `sjk` already show 数据库 first, but "database" only appears at `shujuku`), and English completions for input that cannot be pinyin (`featu`, `gith`) sit after five nonsense Chinese guesses, so the user must type the whole word before English is reachable. The 30,000-word lexicon also misses common workplace terms: 37 of 67 sampled tech/office words (json, refactor, redis, typescript, figma, jira, openai, …) produce no English candidate at all.

## What Changes

- Translate the first Chinese candidate while the pinyin is still incomplete or abbreviated (`shujuk`, `sjk`, `huiy`), not only for fully segmentable pinyin.
- For input of four or more letters that cannot be fully segmented into pinyin, promote the most frequent English completion to the second candidate, directly after the first Chinese candidate. `Space` keeps committing the first candidate.
- Grow the bundled English word list from 30,000 to 100,000 wordfreq words.
- Add a project-maintained supplement of technical and office terms with display casing (GitHub, iOS, macOS, OpenAI, TypeScript, Kubernetes, OKR, …). Matching stays case-insensitive; candidates show the display form; supplement terms rank ahead of rare words.

## Capabilities

### New Capabilities
- `english-candidates-while-typing`: translation of incomplete or abbreviated pinyin and promotion of English completions for non-pinyin input in Chinese mode.
- `english-lexicon`: size, supplement, display casing, and ranking of the bundled English lexicon.

### Modified Capabilities
- (None)

## Impact

- `packages/english-engine`: `EnglishAugmentedChineseEngine` translation and placement rules; `EnglishLexicon` display forms and supplement ranking; regenerated `wordlist.txt`; new `supplement.txt` resource.
- `scripts/english/build-wordlist.py`: default size 100,000.
- English mode also benefits from the larger lexicon and display casing.
- Lexicon load time grows (measured in tests; still loaded once per process).
