## Context

`IntelligenceRecorder` already reads the text before the cursor once a sentence ends, on the next main-actor turn, timed per app, and stopping for slow apps (`add-input-memory`, design 6). Window titles reuse that path. IMK gives no window information, so titles come from the Accessibility API, which needs the user's grant.

## Decisions

### 1. One generic read, title only

`WindowTitleReader.focusedWindowTitle(bundleIdentifier:)`:
1. Takes the frontmost app's pid when it matches the client, else a running instance.
2. Reads `kAXFocusedWindowAttribute` and then `kAXTitleAttribute`.
3. Sets `AXUIElementSetMessagingTimeout` to 0.25 s on both elements.

No per-app code. Web and window contents are never read: Chromium and Electron apps switch on full accessibility support, with more CPU and memory, when assistive clients read their content.

### 2. Same scheduling as context

- The read runs in the recorder's `later` block, after the key has been handled, only for sentences ending on punctuation or `Return` that go to the journal.
- It is timed into `windowStats`, separately from `contextStats`, so a slow title read does not stop context reads.
- An app whose title read takes over 100 ms is not read again until the input method restarts. With the 0.25 s timeout, a hung app costs at most one 0.25 s pause, once.

### 3. Protecting titles

Titles can name people, mailboxes, or pages. `IntelligenceRecorder.windowTitle(_:)` trims a title, cuts it to 120 characters, and drops it entirely if `PrivacyFilter.allowsSentence` fails (for example, "收件箱 – alex@example.com"). Titles are stored only in the journal, so turning off the journal or clearing the records removes them.

### 4. Asking for access

- The menu item toggles `IntelligenceWindowTitlesEnabled`. Turning it on without access calls `AXIsProcessTrustedWithOptions` with the prompt option and opens the Accessibility pane.
- The item's title says access is missing until it is granted.
- The learning page shows the same status. With ad-hoc signing, an update can leave the grant visible but void; the page tells the user to switch it off and on.

## Risks

- Chat apps may title windows with the app name only. The sample titles on the page show which apps are useful before any per-app adapter is considered.
- The grant has to be renewed after updates while builds are ad-hoc signed.
