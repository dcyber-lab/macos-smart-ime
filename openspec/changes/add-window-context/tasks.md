## 1. Reading

- [x] 1.1 `WindowTitleReader`: trust check, prompt, focused window title with a 0.25 s timeout
- [x] 1.2 `InputJournal.Entry.window`; `IntelligenceSettings.isWindowTitlesEnabled` (default false)
- [x] 1.3 `IntelligenceRecorder`: title read in `later`, `windowStats`, slow-app stop, `windowTitle(_:)` cleaning, with tests

## 2. Controls and Page

- [x] 2.1 Menu item 读取窗口标题 with access prompt and status title, with tests
- [x] 2.2 Learning page: sessions split by window, titles in headers, 窗口标题 section with samples and status, with tests

## 3. Verification

- [x] 3.1 Unit tests locally (143 host, 120 data)
- [ ] 3.2 CI
- [ ] 3.3 Live: grant access, type in Chrome, a chat app, Ghostty, and an editor; check sessions, sample titles, and timings
