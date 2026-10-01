## ADDED Requirements

### Requirement: Off Until Enabled
Learning SHALL be off until the user turns on 智能学习 in the input menu. While it is off, no commit SHALL be recorded and no memory file SHALL be created.

#### Scenario: Fresh install
- **WHEN** the user types normally without enabling 智能学习
- **THEN** `input-memory.json` SHALL NOT exist

### Requirement: Only Derived Data on Disk
The memory SHALL persist only per-app language counts and salted sentence fingerprints with counts. Committed text SHALL NOT be written to disk, and the input method SHALL NOT send it over the network.

#### Scenario: Learned sentence
- **WHEN** learning is on and the user commits "这个功能下周上线。" in Slack
- **THEN** the file SHALL contain Slack's updated Chinese count and one fingerprint, and SHALL NOT contain the sentence text

### Requirement: Sensitive Content Is Not Learned
A sentence containing six or more consecutive digits, an email address, a URL, or a token-like string SHALL be dropped whole. Nothing SHALL be recorded in excluded apps, in apps without a bundle identifier, or while secure input is on.

#### Scenario: Verification code
- **WHEN** the user commits "验证码是 482913。"
- **THEN** nothing from that sentence SHALL be recorded

#### Scenario: Terminal
- **WHEN** the user types in Terminal
- **THEN** nothing SHALL be recorded

### Requirement: User Controls
The input menu SHALL offer 智能学习 (on/off), 不在「<current app>」中学习, 查看学习记录…, and 清除学习记录… under the section title 智能中心.

#### Scenario: Exclude the current app
- **WHEN** the user chooses 不在「微信」中学习 while typing in WeChat
- **THEN** WeChat SHALL be added to `IntelligenceExcludedApps`, and later commits there SHALL NOT be recorded

#### Scenario: Clear
- **WHEN** the user chooses 清除学习记录… and confirms
- **THEN** the input memory, candidate history, and translation-learning records SHALL be deleted from disk and memory

#### Scenario: View
- **WHEN** the user chooses 查看学习记录…
- **THEN** a summary of settings, excluded apps, per-app language mix, and fingerprint counts SHALL open, and it SHALL contain no sentence text

### Requirement: No Cost While Typing
Recording SHALL happen only when text is committed. The work SHALL be limited to appending to the sentence buffer and, at a sentence end, one fingerprint. Files SHALL be written off the main thread.

#### Scenario: Fast typing
- **WHEN** learning is on and the user types continuously
- **THEN** key handling time SHALL not change measurably compared with learning off
