# Intelligence Hub

TL;DR: The input method turns what the user commits into a small local memory and offers help at the right moment: better candidates, Chinese-English rewriting, calendar reminders, and quick phrases. Every suggestion waits for a key press. Nothing leaves the Mac, learning is off until the user turns it on, and it can be inspected and wiped. It ships as five OpenSpec changes, foundation first.

## Decisions (user, 2026-10-01)

| Question | Decision |
|---|---|
| Where learned data lives | Only on this Mac; no cloud, no network |
| Which help | All four: better candidates, Chinese-English rewriting, calendar reminders, quick phrases |
| How proactive | Suggest only; the user confirms with a key; never act automatically |

## Principles: privacy first, typing never slower

- **Local only**: no network code in the learning or suggestion path. Models are on-device (Apple Translation, Apple Foundation Models).
- **Off by default**: learning starts only after the user enables 智能学习 in the input menu.
- **Store conclusions, not text**: memory keeps counts and fingerprints. Raw sentences stay in memory for the current suggestion only.
- **Drop sensitive sentences whole**: six or more digits in a row, email addresses, URLs, or token-like strings mean the sentence is not learned.
- **Excluded apps**: password managers and terminals by default, plus any app the user excludes from the menu. Secure text fields are already closed to input methods.
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
2. **Memory (`packages/user-data`)**: bounded, decaying JSON stores like `CandidateHistory`; shared so a future Companion app can show it.
3. **Understanding (async)**: rules first (dates, repetition, app language); Foundation Models only where rules are not enough.
4. **Suggestion (IME UI)**: one chip next to the caret. `Tab` accepts, any other key dismisses. Rate-limited, and each dismissal makes that kind rarer in that app.
5. **Action**: replace the sentence, create an event or reminder, save a phrase, or update candidates. Each is reversible or confirmable.

## Delivery: five OpenSpec changes

| # | Change | Delivers | Depends on |
|---|---|---|---|
| 1 | `add-input-memory` | Privacy shell, sentence assembly, app language profiles, sentence fingerprints, menu controls (智能学习, per-app exclusion, view, clear) | — |
| 2 | `add-suggestion-chip` | Chip UI, `Tab` to accept, rate limits, feedback; first provider: calendar reminders (EventKit) | 1 |
| 3 | `add-quick-phrases` | "存成短语" on the third repetition; phrases come back as candidates by pinyin initials | 1, 2 |
| 4 | `add-rewrite-suggestions` | "转成英文" in English-dominant apps; polish actions for selected text with Foundation Models | 1, 2 |
| 5 | `add-personal-terms` | Terms typed in pieces become words; per-app candidate order (English first in code editors) | 1 |

## Open risks

- Apple Intelligence is off on the dev Mac (`appleIntelligenceNotEnabled`); polish actions need it. "转成英文" falls back to Apple Translation.
- `NSDataDetector` misses "3点开会" and reports bare dates ("今天天气不错"). Reminders require a time of day; a small rule covers "N点".
- Replacing an already committed sentence needs the client to honor `replacementRange`; where it does not, the suggestion copies the result instead.
- `Tab` is meaningful in many apps; it is captured only while a chip is visible.
