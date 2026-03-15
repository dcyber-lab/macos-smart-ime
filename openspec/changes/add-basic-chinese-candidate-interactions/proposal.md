# Proposal

## Summary

Add the first user-facing Chinese candidate interactions on top of the current `librime` bridge:

- `Space` selects the first candidate when composition is active
- number keys select visible candidates
- `Escape` clears the current composition without committing text

## Why

The current `SmartIMEHost` can be installed and can route Chinese input through `librime`, but the interaction loop is still incomplete. Users can type and see composition updates, yet basic candidate acceptance and clearing behavior is not stable enough for real use.

This change keeps the scope narrow and focused on the current Chinese path. It does not add English features, candidate paging, or a richer UI.

## Goals

- Make the current Chinese path usable for simple candidate commit flows
- Keep candidate handling inside the IME real-time path
- Reuse the current `rime-bridge` update model instead of adding a second candidate state source

## Non-Goals

- English mode or English completion
- Candidate paging
- Mouse candidate selection
- Rich mode switching
- New architecture beyond the current Chinese IME flow
