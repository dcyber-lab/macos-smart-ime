## ADDED Requirements

### Requirement: Commit Effect
When committed text matches a row of the visible candidate panel, that row SHALL play the selected effect, and the text SHALL be inserted before the effect starts. Commits that match no row SHALL play nothing.

#### Scenario: Space commits the first candidate
- **WHEN** the user types `nihao` and presses `Space`
- **THEN** 你好 SHALL be inserted, and the 你好 row SHALL break apart while the rest of the panel fades out

#### Scenario: Number key picks another row
- **WHEN** 你好 is highlighted and the user presses `4` to commit 你号
- **THEN** the 你号 row SHALL play the effect

#### Scenario: Punctuation commits
- **WHEN** the user types `nihao` and `，`, committing 你好，
- **THEN** the 你好 row SHALL play the effect, not the 你 row

#### Scenario: English mode
- **WHEN** the user types `deplo` in English mode and commits deploy with `Space`
- **THEN** the deploy row SHALL play the effect

#### Scenario: Cancel or raw input
- **WHEN** the user presses `Escape`, or `Return` commits raw pinyin in Chinese mode
- **THEN** no effect SHALL play

#### Scenario: Typing continues
- **WHEN** the user types the next letter while an effect is playing
- **THEN** the new panel SHALL appear immediately and fully visible, and key handling SHALL not wait for the effect

### Requirement: Skins
The effect SHALL combine a motion (玻璃炸裂, 碎裂下坠, 粒子消散, 随机, or 关闭) with a palette (彩虹, 霓虹, 马卡龙, 跟随强调色, or 随机). The defaults SHALL be 玻璃炸裂 and 彩虹. 随机 SHALL choose again on every commit. With a colored palette, text fragments SHALL stay white.

#### Scenario: Off
- **WHEN** the motion is 关闭
- **THEN** commits SHALL hide the panel without an effect

#### Scenario: Reduce Motion
- **WHEN** Reduce Motion is on in Accessibility settings
- **THEN** no effect SHALL play, whatever the setting

### Requirement: Switching Skins
While the input method is active, its input menu SHALL list the choices under the section titles 选词动效 and 碎片配色, without submenus, with a check mark on the current choice. Choosing an item SHALL save it, apply it to the next commit, and play a preview near the pointer. The same settings SHALL be writable with `defaults write lab.dcyber.inputmethod.smartime CommitEffect …` and `CommitEffectPalette …`.

#### Scenario: Pick a palette from the menu
- **WHEN** the user chooses 霓虹 under 碎片配色
- **THEN** a neon preview SHALL play near the pointer, and the next commit SHALL use neon colors
