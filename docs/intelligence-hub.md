# Intelligence Hub

TL;DR: The input method turns what the user commits into a local memory and offers help at the right moment: better candidates, Chinese-English rewriting, calendar reminders, and quick phrases. Every suggestion waits for a key press. Nothing leaves the Mac, learning is off until the user turns it on, and it can be inspected and wiped. While learning is on, committed sentences are also kept as a 30-day input journal by default, as a trial the user can switch off. It ships as five OpenSpec changes, foundation first.

## Decisions (user, 2026-10-01)

| Question | Decision |
|---|---|
| Where learned data lives | Only on this Mac; no cloud, no network |
| Which help | All four: better candidates, Chinese-English rewriting, calendar reminders, quick phrases |
| How proactive | Suggest only; the user confirms with a key; never act automatically |
| Raw text | Kept as an optional input journal, on by default while learning is on, 30 days, plain local file; a trial to judge usefulness, switched off if it does not pay off |

## Principles: privacy first, typing never slower

- **Local only**: no network code in the learning or suggestion path. Models are on-device (Apple Translation, Apple Foundation Models).
- **Off by default**: learning starts only after the user enables 智能学习 in the input menu.
- **Conclusions always, text optionally**: memory keeps counts and fingerprints. The input journal (保存输入原文) adds the sentences themselves: on by default, 30-day retention, one file per day, mode 0600, excluded from Time Machine. It is not encrypted during the trial: any process running as the user can read it.
- **Drop sensitive sentences whole**: six or more digits in a row, email addresses, URLs, or token-like strings mean the sentence is not learned.
- **Excluded apps**: password managers and terminals by default, plus any app the user excludes from the menu. A default can be lifted from the menu, for example for a terminal used to talk to AI tools. Secure text fields are already closed to input methods.
- **Visible and erasable**: the menu shows what was learned and clears it.
- **Off the key path**: recording happens on commit and costs microseconds; analysis and models run asynchronously after the key is handled.

## Four kinds of help

| Help | Example | Signal | On-device technique |
|---|---|---|---|
| Better candidates | A colleague's name or project term becomes candidate 1 after a few uses | Terms committed in pieces, per-app language mix | Counting; librime user dictionary |
| Chinese-English rewriting | After a Chinese sentence in GitHub or an English email: "✨ 转成英文 ⇥" | App language mix, sentence end | Apple Translation; Foundation Models for polish when Apple Intelligence is on |
| Calendar reminders | "明天下午三点和 Alex 过方案" → "✨ 加到日历 ⇥" | Date with a time of day in the sentence | `NSDataDetector` (probed: handles 明天下午三点, 10月8号晚上7点, 后天 14:30); EventKit |
| Quick phrases | The third time the same long sentence is typed: "✨ 存成短语 ⇥" | Repeated sentence fingerprint | Salted hashes, counts |

## Architecture: capture → memory → understanding → suggestion → action

1. **Capture (IME)**: committed text, client app (`IMKTextInput.bundleIdentifier()`), time. A sentence assembler joins commits until punctuation, Return, a pause, or a focus change.
2. **Memory (`packages/user-data`)**: bounded, decaying JSON stores like `CandidateHistory`, plus the optional journal (`journal/YYYY-MM-DD.jsonl`); shared so a future Companion app can show it.
3. **Understanding (async)**: rules first (dates, repetition, app language); Foundation Models only where rules are not enough.
4. **Suggestion (IME UI)**: one chip next to the caret. `Tab` accepts, any other key dismisses. Rate-limited, and each dismissal makes that kind rarer in that app.
5. **Action**: replace the sentence, create an event or reminder, save a phrase, or update candidates. Each is reversible or confirmable.

## Context

- **Text before the cursor** (no extra permission, in step 1): through IMK, once per sentence, after the key. Timed per app; stops for apps slower than 100 ms. Shown on the learning page.
- **Sessions**: the journal is shown as conversations (same app, gaps of 10 minutes or less).
- **Window titles** (`add-window-context`, needs Accessibility, off by default; menu 读取窗口标题):
  - The permission itself costs nothing. Each read is a round trip to the app, usually 0.1 to a few ms, but up to the 6 s default messaging timeout if the app hangs. So reads happen only on app switch or sentence end, off the key path, with a 0.25 s timeout.
  - The plan reads only the focused window's title, never web content: Chromium and Electron apps switch on full accessibility support, and use more CPU and memory, when assistive clients read their content.
  - One generic call works for almost every app; how useful the title is varies. Browser page titles, editor file names, and terminal titles are informative. Chat apps such as WeChat and SeaTalk may only show the app name, and the conversation name or a browser URL would need per-app adapters that break with app updates. The learning page shows sample titles per app before any adapter is written.
  - The Accessibility grant is tied to the code signature. While builds are ad-hoc signed, an update may need the user to switch LinguaType off and on in the Accessibility list.
- **Not planned**: reading what other people wrote in chat windows.

## Seeing what was learned

查看学习记录 opens a local page that starts with 学到了什么: frequent words, possible new words, repeated sentences, sentences naming a time, and each app's writing language. Each section names the step that will act on it, so the value of each later step is visible before it ships.

## Delivery: five OpenSpec changes

| # | Change | Delivers | Depends on |
|---|---|---|---|
| 1 | `add-input-memory` | Privacy shell, sentence assembly, app language profiles, sentence fingerprints, the input journal, menu controls (智能学习, 保存输入原文, per-app exclusion, view and search, clear) | — |
| 2 | `add-suggestion-chip` | Chip UI, `Tab` to accept, rate limits, feedback; first provider: calendar reminders (EventKit) | 1 |
| 3 | `add-quick-phrases` | "存成短语" on the third repetition; phrases come back as candidates by pinyin initials | 1, 2 |
| 4 | `add-rewrite-suggestions` | "转成英文" in English-dominant apps; polish actions for selected text with Foundation Models | 1, 2 |
| 5 | `add-personal-terms` | Terms typed in pieces become words; per-app candidate order (English first in code editors) | 1 |

## AI providers (measured 2026-10-01, for change 4)

The same rewrite prompt ("这个功能下周上线，麻烦大家帮忙回归一下" → English) was sent through each provider:

| Provider | Account | Latency | Note |
|---|---|---|---|
| Apple Foundation Models | none | — | Supports Chinese; unavailable until Apple Intelligence is enabled |
| `claude -p --model haiku` | Claude subscription | 8.6 s | Loads the user's hooks and plugins |
| same, with `--setting-sources project --tools "" --strict-mcp-config --no-session-persistence`, empty working dir | Claude subscription | 4–6 s | No tools, no saved session |
| `claude -p --bare` | API key only | — | Refuses subscription login |
| `codex exec --skip-git-repo-check --ephemeral -s read-only` | ChatGPT subscription | 11 s | Agent with read-only file access |

- Both CLIs work for explicit, confirmed actions with a "思考中…" state. None is fast enough for anything while typing.
- A cloud provider sends the current sentence or selection off the Mac. That needs the user to amend the local-only decision for confirmed actions only; learned memory and the journal never leave.
- Launch the CLI by absolute path (the input method has no login-shell `PATH`), pass the text as an argument array, use a timeout, and cancel on dismiss.

## Open risks

- The journal is a plain file during the trial. Encrypting it with a Keychain key is deferred: with ad-hoc signing every update changes the code signature and would prompt for Keychain access mid-typing. Revisit with Developer ID signing or if the journal is kept.

- Apple Intelligence is off on the dev Mac (`appleIntelligenceNotEnabled`); polish actions need it. "转成英文" falls back to Apple Translation.
- `NSDataDetector` misses "3点开会" and reports bare dates ("今天天气不错"). Reminders require a time of day; a small rule covers "N点".
- `NSDataDetector` parses Chinese dates only when Chinese is among the user's preferred languages (`AppleLanguages`). With an English-only list, "明天下午三点" finds nothing. Reminders need a project-owned parser for common Chinese expressions (今天/明天/后天/下周X, 上午/下午/晚上, N点[半]).
- Replacing an already committed sentence needs the client to honor `replacementRange`; where it does not, the suggestion copies the result instead.
- `Tab` is meaningful in many apps; it is captured only while a chip is visible.
