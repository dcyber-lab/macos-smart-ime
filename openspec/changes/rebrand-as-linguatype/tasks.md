## 1. Icons

- [x] 1.1 Add `scripts/branding/make-icons.swift` generating `LinguaType.tiff` (template menu icon) and `LinguaType.icns` (app icon)
- [x] 1.2 Render previews (menu icon at 1× and 2× on light and dark bars, app icon at several sizes) for user review

## 2. Names and Resources

- [x] 2.1 Update `Info.plist` (display name fallback, icon files, `TISIconIsTemplate`) and both `InfoPlist.strings`; remove `SmartIMEHost.icns`
- [x] 2.2 Rename the Rime schema display name to 灵译拼音

## 3. Verification and Docs

- [x] 3.1 Deploy with `scripts/ime/dev-cycle.sh`; confirm TIS reports the new localized name and the smoke test passes
- [x] 3.2 Update `docs/implementation-log.md` and README references to the user-facing name
