## ADDED Requirements

### Requirement: Off Until Enabled
Learning SHALL be off until the user turns on 智能学习 in the input menu. While it is off, no commit SHALL be recorded and no memory file SHALL be created.

#### Scenario: Fresh install
- **WHEN** the user types normally without enabling 智能学习
- **THEN** `input-memory.json` SHALL NOT exist

### Requirement: Derived Memory
While learning is on, the memory SHALL persist per-app language counts and salted sentence fingerprints with counts, and no sentence text. The input method SHALL NOT send committed text or learned data over the network.

#### Scenario: Learned sentence
- **WHEN** learning is on and the user commits "这个功能下周上线。" in Slack
- **THEN** `input-memory.json` SHALL contain Slack's updated Chinese count and one fingerprint, and SHALL NOT contain the sentence text

### Requirement: Input Journal
While learning is on and 保存输入原文 is on (the default), each allowed sentence SHALL be appended with its app and time to that day's journal file. Journal files SHALL be readable only by the user, excluded from backups, and deleted after the retention period (default 30 days).

#### Scenario: Journal entry
- **WHEN** learning and the journal are on and the user commits "这个功能下周上线。" in Slack
- **THEN** today's journal file SHALL contain that sentence with Slack's bundle identifier and the time

#### Scenario: Journal off
- **WHEN** the user turns 保存输入原文 off
- **THEN** no further sentences SHALL be appended, while the derived memory keeps learning

#### Scenario: Retention
- **WHEN** a journal day file is older than the retention period
- **THEN** it SHALL be deleted at the next launch or daily check

### Requirement: Sensitive Content Is Not Learned
A sentence containing six or more consecutive digits, an email address, a URL, or a token-like string SHALL be dropped whole. Nothing SHALL be recorded in excluded apps, in apps without a bundle identifier, or while secure input is on.

#### Scenario: Verification code
- **WHEN** the user commits "验证码是 482913。"
- **THEN** nothing from that sentence SHALL be recorded

#### Scenario: Terminal
- **WHEN** the user types in Terminal without having allowed it
- **THEN** nothing SHALL be recorded

#### Scenario: Allowing a default exclusion
- **WHEN** the user unchecks 不在「Ghostty」中学习
- **THEN** sentences typed in Ghostty SHALL be recorded, still subject to the sentence rules

### Requirement: User Controls
The input menu SHALL offer 智能学习 (on/off), 保存输入原文 (on/off), 不在「<current app>」中学习, 查看学习记录…, and 清除学习记录… under the section title 智能中心.

#### Scenario: Exclude the current app
- **WHEN** the user chooses 不在「微信」中学习 while typing in WeChat
- **THEN** WeChat SHALL be added to `IntelligenceExcludedApps`, and later commits there SHALL NOT be recorded

#### Scenario: Clear
- **WHEN** the user chooses 清除学习记录… and confirms
- **THEN** the input memory, the journal, candidate history, and translation-learning records SHALL be deleted from disk and memory

#### Scenario: View
- **WHEN** the user chooses 查看学习记录…
- **THEN** a local page SHALL open with settings, excluded apps, per-app language mix, fingerprint counts, and, when the journal is on, the recent sentences with a search box

### Requirement: No Cost While Typing
Recording SHALL happen only when text is committed. The work SHALL be limited to appending to the sentence buffer and, at a sentence end, one fingerprint. Files SHALL be written off the main thread.

#### Scenario: Fast typing
- **WHEN** learning is on and the user types continuously
- **THEN** key handling time SHALL not change measurably compared with learning off
