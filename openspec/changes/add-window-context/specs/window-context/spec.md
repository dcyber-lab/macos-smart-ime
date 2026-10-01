## ADDED Requirements

### Requirement: Opt-In Window Titles
Reading window titles SHALL be off until the user turns on 读取窗口标题. Turning it on without Accessibility access SHALL show the system prompt and open the Accessibility settings, and the menu item SHALL say access is needed until it is granted.

#### Scenario: Turning it on
- **WHEN** learning is on and the user chooses 读取窗口标题 without Accessibility access
- **THEN** the system access prompt SHALL appear and the menu item SHALL read 读取窗口标题（需授权辅助功能）

### Requirement: Title With the Sentence
When window titles are on and access is granted, a sentence that ends on punctuation or `Return` and goes to the journal SHALL be stored with the focused window's title. Only the title SHALL be read, after the key has been handled, with a 0.25 s timeout. Reads SHALL stop for an app after one takes over 100 ms. Titles that look sensitive SHALL be dropped.

#### Scenario: Browser tab
- **WHEN** the user types 看下这个 PR。 in Chrome on a page titled "PR #14 · macos-smart-ime"
- **THEN** the journal entry SHALL have that window title

#### Scenario: Mailbox title
- **WHEN** the window title contains an email address
- **THEN** the entry SHALL have no window title

### Requirement: Titles on the Learning Page
The learning page SHALL split sessions when the window changes and show the window title in each session header. It SHALL show the window title setting and access status and, per app, reads, hits, timings, and up to three sample titles.

#### Scenario: Two tabs
- **WHEN** the user types in Chrome on a Google page and then on a PR page
- **THEN** the page SHALL show two sessions, each with its window title
