## 1. Bundle Display Metadata

- [x] 1.1 Add `CFBundleDisplayName` and `tsInputMethodLanguageKey` to the IME bundle metadata
- [x] 1.2 Add localized `InfoPlist.strings` resources for the input method display name

## 2. Install Workflow Repair

- [x] 2.1 Extend the install workflow to repair malformed `AppleEnabledInputSources` entries for the logged-in user
- [x] 2.2 Ensure the install workflow de-duplicates and re-enables a valid `SmartIMEHost` entry
- [x] 2.3 Refresh user-facing macOS input-source agents after installation

## 3. Verification and Docs

- [x] 3.1 Rebuild and reinstall `SmartIMEHost` after the workflow changes
- [x] 3.2 Verify the repaired preferences no longer contain malformed `Keyboard Input Method` entries without `Bundle ID`
- [x] 3.3 Update local validation docs and implementation log for switcher visibility
