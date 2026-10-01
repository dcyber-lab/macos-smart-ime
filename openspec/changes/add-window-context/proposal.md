## Why

The journal shows what the user typed and in which app, but not where in the app: which chat, document, web page, or terminal session. The user asked for more context and accepted Accessibility access for it. The window title is the cheapest signal that answers "where" in most apps.

## What Changes

- New menu item under 智能中心: 读取窗口标题. It is off by default and only available while learning is on. Turning it on asks for Accessibility access (system prompt, then the Privacy & Security pane); until access is granted, the item reads 读取窗口标题（需授权辅助功能）.
- When a sentence ends on punctuation or `Return`, after the key has been handled, the input method reads the focused window's title of the app being typed in and stores it with the journal entry (`win`).
  - Only the title is read, never window contents.
  - Each call has a 0.25 s timeout. Reads are timed per app and stop for an app after one takes over 100 ms.
  - A title is cut to 120 characters and dropped if it looks sensitive (email, URL, digits, token).
- Learning page:
  - Sessions also split when the window changes, and show the window title.
  - A 窗口标题 section shows the setting and access status and, per app, reads, hits, timings, and up to three sample titles.

## Non-goals

- Reading window or web content, URLs, or chat partner names inside apps (per-app adapters); decided later from the sample titles.
- Reading anything while typing, or when learning or the journal is off.

## Capabilities

### New Capabilities
- `window-context`: when window titles are read, how they are protected, and what the user sees.

## Impact

- New in `IMEHostCore`: `WindowTitleReader` (Accessibility, timeout).
- `IntelligenceSettings` (`IntelligenceWindowTitlesEnabled`), `IntelligenceRecorder` (title reads and `windowStats`), `IntelligenceMenu`, `LearningPage`, `IMEInputController`.
- `UserData`: `InputJournal.Entry.window`.
- Ad-hoc signing: macOS ties the Accessibility grant to the code signature, so each update may need the user to switch LinguaType off and on again in the Accessibility list.
