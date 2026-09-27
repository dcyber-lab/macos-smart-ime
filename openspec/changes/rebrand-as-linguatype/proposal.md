## Why

The input menu shows the development name "SmartIMEHost" next to a generic green checkmark app icon, which looks unfinished next to Pinyin, ABC, and Squirrel. The user chose the product name LinguaType (灵译输入法) and a bilingual "中/A" icon.

## What Changes

- Show "灵译输入法" on Chinese systems and "LinguaType" elsewhere (localized `CFBundleDisplayName` / `CFBundleName`), and name the Rime schema "灵译拼音".
- Replace the menu icon with a template icon (`LinguaType.tiff`): a rounded square with "中" (top left) and "A" (bottom right) cut out, rendered by macOS in the menu bar's light or dark style (`TISIconIsTemplate`).
- Replace the app icon (`LinguaType.icns`) with a gradient rounded square carrying the same "中/A" glyphs.
- Generate both icons from `scripts/branding/make-icons.swift` so they can be adjusted and regenerated.
- Internal names stay the same: bundle `SmartIMEHost.app`, bundle identifier `lab.dcyber.inputmethod.smartime`, process name, scripts, and defaults domain.

## Capabilities

### New Capabilities
- `input-method-branding`: display names and icons shown by macOS for the input method.

### Modified Capabilities
- (None)

## Impact

- `apps/ime/Resources`: `Info.plist`, `en.lproj` / `zh-Hans.lproj` `InfoPlist.strings`, new `LinguaType.tiff` and `LinguaType.icns` (the old `SmartIMEHost.icns` is removed).
- `third_party/librime-data/smartime/smartime_pinyin.schema.yaml`: schema display name.
- `scripts/branding/make-icons.swift`: icon generator.
- macOS may cache the old name and icon until the input source is re-registered; `install-host.sh` already re-registers and restarts the text input menu.
