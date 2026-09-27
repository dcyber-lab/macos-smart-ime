## ADDED Requirements

### Requirement: Localized Name
The input method SHALL be shown as "灵译输入法" when the system language is Simplified Chinese and as "LinguaType" otherwise.

#### Scenario: English system
- **WHEN** the primary system language is English
- **THEN** the input menu and Keyboard settings SHALL show "LinguaType"

#### Scenario: Chinese system
- **WHEN** the primary system language is Simplified Chinese
- **THEN** the input menu and Keyboard settings SHALL show "灵译输入法"

### Requirement: Template Menu Icon
The menu icon SHALL be a monochrome template image of a rounded square with "中" and "A" cut out, rendered by macOS to match light and dark menu bars.

#### Scenario: Dark menu bar
- **WHEN** the menu bar uses a dark appearance
- **THEN** the icon SHALL be drawn in the menu bar's light foreground color

### Requirement: App Icon
The app icon SHALL show the same "中/A" glyphs in white on a colored rounded square.

#### Scenario: Keyboard settings
- **WHEN** the user opens the input source list in Keyboard settings
- **THEN** the input method SHALL show the new app icon instead of the green checkmark
