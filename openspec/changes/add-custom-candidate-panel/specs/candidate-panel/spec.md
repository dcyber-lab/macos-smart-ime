## ADDED Requirements

### Requirement: Vertical Candidate Panel
The host SHALL display candidates in its own vertical panel, one numbered row per candidate, with rounded corners and a background that follows the system light or dark appearance.

#### Scenario: Candidates shown as numbered rows
- **WHEN** the composition has candidates 数据库, 数据, 书局
- **THEN** the panel SHALL show three rows labeled 1, 2, 3 in that order

#### Scenario: Height fits the candidates
- **WHEN** the composition has three candidates
- **THEN** the panel SHALL be exactly tall enough for three rows, with no empty rows below them

#### Scenario: Panel resizes while typing
- **WHEN** the candidate list changes from six candidates to two
- **THEN** the panel SHALL shrink to fit two rows

#### Scenario: Dark appearance
- **WHEN** the system appearance is dark
- **THEN** the panel background and text SHALL use dark-appearance colors

#### Scenario: No candidates
- **WHEN** the composition is empty or has no candidates
- **THEN** the panel SHALL be hidden

### Requirement: Highlighted Row
The row matching the composition's selected candidate index SHALL be drawn with a soft tint of the system accent color as its background and accent-colored text.

#### Scenario: Arrow key moves the highlight
- **WHEN** the first row is highlighted and the user presses `Down`
- **THEN** the second row SHALL be drawn highlighted and the first row SHALL not

### Requirement: Mixed-Language Grouping
When the candidate list contains both Chinese and English candidates, the panel SHALL draw a separator wherever consecutive rows switch between Chinese and English, and SHALL tag English rows with a small capsule label: 译 for translations and 英 for English words. When the list contains only one kind, the panel SHALL draw no tags and no separators.

#### Scenario: Translation after Chinese candidates
- **WHEN** the candidates are 数据库, 数据, database (translation)
- **THEN** a separator SHALL appear between 数据 and database, and database SHALL carry the tag 译

#### Scenario: English word before Chinese candidates
- **WHEN** the candidates are hello (English word), 合理, 荷兰
- **THEN** hello SHALL carry the tag 英 and a separator SHALL appear between hello and 合理

#### Scenario: English mode list
- **WHEN** all candidates are English completions
- **THEN** no row SHALL carry a tag and no separator SHALL be drawn

### Requirement: Preedit Header
In Chinese mode, the panel SHALL show the text being composed (the Rime preedit) in small secondary text above the candidate rows. In English mode, the panel SHALL NOT show the header.

#### Scenario: Pinyin shown above candidates
- **WHEN** the user types `shujuku` in Chinese mode
- **THEN** the panel SHALL show the preedit (e.g. "shu ju ku") above the first candidate row

#### Scenario: English mode has no header
- **WHEN** the user types `he` in English mode
- **THEN** the panel SHALL show only candidate rows

### Requirement: Page Indicator
When the Chinese candidate list has more than one page, the header SHALL show an up chevron if an earlier page exists and a down chevron if a later page exists. A single-page list SHALL show no chevrons.

#### Scenario: First of several pages
- **WHEN** the first page is shown and more pages exist
- **THEN** the header SHALL show a down chevron and no up chevron

#### Scenario: Middle page
- **WHEN** a page other than the first is shown and more pages follow
- **THEN** the header SHALL show both an up and a down chevron

#### Scenario: Single page
- **WHEN** all candidates fit on one page
- **THEN** no chevrons SHALL be shown

### Requirement: Panel Placement
The panel SHALL appear just below the caret. When there is not enough room below the caret on the current screen, the panel SHALL appear above the caret. The panel SHALL stay horizontally within the screen's visible area.

#### Scenario: Room below the caret
- **WHEN** the caret is in the upper part of the screen
- **THEN** the panel's top edge SHALL be just below the caret's bottom edge

#### Scenario: Caret near the bottom of the screen
- **WHEN** placing the panel below the caret would cross the bottom of the visible screen area
- **THEN** the panel's bottom edge SHALL be just above the caret's top edge

#### Scenario: Caret near the right edge
- **WHEN** placing the panel at the caret would extend past the right edge of the visible screen area
- **THEN** the panel SHALL be shifted left so it fits

#### Scenario: Client reports no caret rectangle
- **WHEN** the client returns an empty caret rectangle
- **THEN** the panel SHALL reuse its last position, or appear at the mouse location if it has none

### Requirement: Candidate Selection
Keyboard selection (number keys, arrow highlight, `Space`, `Return`, `Escape`) SHALL behave as before. Clicking a row SHALL select that candidate exactly as pressing its number key does.

#### Scenario: Click a translation row
- **WHEN** the user clicks the row for database
- **THEN** database SHALL be committed and the panel SHALL be hidden

#### Scenario: Composition ends
- **WHEN** a candidate is committed, the composition is cancelled with `Escape`, or the input method is deactivated
- **THEN** the panel SHALL be hidden
