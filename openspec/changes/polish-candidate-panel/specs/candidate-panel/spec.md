## MODIFIED Requirements

### Requirement: Highlighted Row
The row matching the composition's selected candidate index SHALL be drawn with a solid fill in the system accent color. The candidate text SHALL be white. The row number, gloss, and tag SHALL be white or translucent white.

#### Scenario: Arrow key moves the highlight
- **WHEN** the first row is highlighted and the user presses `Down`
- **THEN** the second row SHALL be drawn with the accent fill and white text, and the first row SHALL be drawn normally

#### Scenario: Highlighted translation row
- **WHEN** the highlighted row is a translation with the tag 译
- **THEN** the tag SHALL be drawn in white on a translucent white capsule

### Requirement: Preedit Header
In Chinese mode, the panel SHALL show the text being composed (the Rime preedit) in secondary text above the candidate rows, separated from the rows by a hairline. In English mode, the panel SHALL NOT show the header.

#### Scenario: Pinyin shown above candidates
- **WHEN** the user types `shujuku` in Chinese mode
- **THEN** the panel SHALL show the preedit (e.g. "shu ju ku") above a hairline and the first candidate row below it

#### Scenario: English mode has no header
- **WHEN** the user types `he` in English mode
- **THEN** the panel SHALL show only candidate rows

### Requirement: Page Indicator
When the Chinese candidate list has more than one page, the header SHALL show an up and a down chevron in fixed positions. A chevron whose direction has no page SHALL be drawn dimmed. A single-page list SHALL show no chevrons.

#### Scenario: First of several pages
- **WHEN** the first page is shown and more pages exist
- **THEN** the header SHALL show a dimmed up chevron and a normal down chevron

#### Scenario: Middle page
- **WHEN** a page other than the first is shown and more pages follow
- **THEN** the header SHALL show both chevrons normally

#### Scenario: Last page
- **WHEN** the last of several pages is shown
- **THEN** the header SHALL show a normal up chevron and a dimmed down chevron

#### Scenario: Single page
- **WHEN** all candidates fit on one page
- **THEN** no chevrons SHALL be shown
