## 1. IME Host Candidate Presentation

- [x] 1.1 Add explicit `IMKCandidates` management so active Chinese candidates are shown and hidden with composition state
- [x] 1.2 Keep inline composition updates and candidate-panel updates in sync after every handled Chinese input event
- [x] 1.3 Hide candidate UI and clear host session state on commit, cancel, deactivation, or controller close

## 2. Chinese Commit Flow

- [x] 2.1 Keep bridge-backed key handling for Chinese composition updates and key-driven candidate acceptance
- [x] 2.2 Commit final candidate-panel selections into the focused client and reset the `librime` session cleanly
- [x] 2.3 Ensure `Escape` cancels active composition without leaking raw key input into the client

## 3. Validation And Documentation

- [x] 3.1 Rebuild `SmartIMEHost` and verify the host still compiles after candidate-loop changes
- [x] 3.2 Update manual validation and implementation notes so this milestone requires real GUI verification of `nihao`-style input
- [x] 3.3 Verify the remaining gap, if any, is captured factually in docs and task status
