## Context

`Info.plist` sets `CFBundleDisplayName` to SmartIMEHost, both `InfoPlist.strings` files repeat it, and `CFBundleIconFile` / `tsInputMethodIconFileKey` both point to a colorful 256 px `SmartIMEHost.icns`. System input sources use monochrome template glyphs in rounded squares (拼, A); Squirrel ships a vector `rime.pdf` menu icon.

## Goals / Non-Goals

**Goals:**
- A product name that matches the user's LinguaType branding in both languages.
- A crisp menu icon that follows the menu bar appearance like the system input sources.

**Non-Goals:**
- Renaming the bundle, executable, bundle identifier, defaults domain, or install paths (that would force users to re-add the input source and break scripts and tests).
- Marketing artwork beyond the two icons.

## Decisions

### 1. Localized display name only
`InfoPlist.strings` sets `CFBundleDisplayName` and `CFBundleName` to 灵译输入法 (zh-Hans) and LinguaType (en); `Info.plist`'s `CFBundleDisplayName` becomes LinguaType as the fallback. `CFBundleName` in `Info.plist` stays `$(PRODUCT_NAME)` so the executable and bundle keep their names.

### 2. Vector template menu icon
`make-icons.swift` builds the menu icon by subtracting the outlines of "中" (PingFang SC Semibold) and "A" (SF Pro Semibold) from a rounded square (`CGPath.subtracting`) and writes it as a 16 × 16 pt PDF filled with the nonzero rule. `tsInputMethodIconFileKey` points to `LinguaType.pdf` and `TISIconIsTemplate` is true, so macOS tints it for light and dark menu bars. The first version relied on an even-odd fill for the holes; it rendered correctly through `NSImage` but the input menu showed a solid square, so the holes are now part of the geometry and do not depend on the fill rule.

### 3. App icon from the same glyph layout
The generator renders the app icon at every `.iconset` size (16–1024 px): a rounded square with an indigo-to-teal gradient, subtle top highlight, and white "中/A" glyphs, then runs `iconutil` to produce `LinguaType.icns` for `CFBundleIconFile`.

## Risks / Trade-offs

- [macOS caches input source names and icons] → `install-host.sh` re-registers the source and restarts `TextInputMenuAgent`; if the old icon persists, removing and re-adding the input source or logging out refreshes it.
- [Two glyphs in 16 pt are small] → Glyph sizes and positions are checked at 1× and 2× in rendered previews before deploying.
