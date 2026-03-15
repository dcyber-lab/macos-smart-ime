## 1. IME Interaction Handling

- [x] 1.1 Keep `Space` candidate commit on the current Chinese path engine-driven and document that the host forwards the raw key event
- [x] 1.2 Keep number-key candidate selection on the current Chinese path engine-driven and document that the host forwards the raw key event
- [x] 1.3 Add `Escape` composition cancel behavior that resets both engine and local session state

## 2. Validation

- [x] 2.1 Add or update manual validation notes for the new Chinese candidate interactions
- [ ] 2.2 Verify `Space`, number-key selection, and `Escape` behavior in a normal macOS text client, including that consumed keys do not leak raw characters into the client
