## Context

The repository already has a buildable `SmartIMEHost` app target, a working `librime` bridge, an install workflow, and menu-bar switcher visibility fixes. What is still missing is the first user-visible Chinese input loop in a normal macOS text client.

Today the host can ask `librime` for composition text and candidates, but the milestone is not complete until those candidates are actually visible to the user and can be selected to commit Chinese text. The current code path relies on `updateComposition()` and `candidates(_:)` alone, which is too implicit for this milestone because it does not guarantee that the candidate list is surfaced as a visible candidate panel during interactive typing.

## Goals / Non-Goals

**Goals:**
- Show inline composition for active Chinese input sessions
- Show a visible candidate list backed by the current `librime` candidate array
- Allow candidate acceptance through the current key-driven path and through the candidate panel's final selection callback
- Reset host and engine state cleanly after commit or cancel
- Define a manual validation path that proves `nihao` can become committed Chinese text in a real macOS editor

**Non-Goals:**
- Introduce English routing, completion, or correction
- Add paging, advanced candidate annotations, or custom candidate ranking
- Add AI, network calls, or long-running processing in the IME path
- Build the Companion app or clipboard workflows

## Decisions

### Use `IMKCandidates` explicitly for candidate visibility

The host should manage an `IMKCandidates` panel directly instead of assuming `updateComposition()` alone is sufficient to make candidates visible. This keeps the milestone focused on a reliable, user-visible Chinese loop.

Alternative considered:
- Keep relying only on `updateComposition()` and `candidates(_:)`
  - Rejected because current behavior is not producing a verified visible candidate workflow in real use.

### Keep `librime` as the source of candidate data and default key-driven selection

The candidate array should still come from `librime`, and normal number-key / space-key selection should continue to flow through the bridge when possible. The host should not invent a parallel scoring or candidate-generation layer.

Alternative considered:
- Implement a host-owned candidate list independent of `librime`
  - Rejected because it would duplicate Chinese input logic that belongs in `librime`.

### Let the host commit the final candidate-panel selection and reset the engine session

When the candidate panel reports a final candidate selection, the host should commit that selected text into the client and then clear both local and engine state. This makes mouse or panel-driven final selection deterministic even if the exact key path was not consumed by the bridge.

Alternative considered:
- Require every final selection to round-trip back into `librime` before commit
  - Rejected for this milestone because it adds complexity without improving the initial user-visible loop.

### Hide candidate UI whenever composition becomes inactive

The candidate panel should be shown only when there is active composition with visible candidates, and it should be hidden immediately after commit, cancel, deactivation, or controller close.

Alternative considered:
- Keep the candidate panel resident and only refresh its contents
  - Rejected because it risks stale UI and makes the first milestone harder to reason about.

## Risks / Trade-offs

- [Candidate panel behavior may differ slightly from Apple's built-in Pinyin UX] -> Keep this milestone limited to visibility and correct commit/cancel semantics, not visual parity
- [Panel-driven final selection can diverge from the bridge's exact internal state] -> Reset the `librime` session after final commit so stale composition does not linger
- [Real GUI validation is still required] -> Update the manual checklist and treat local build success as necessary but not sufficient

## Migration Plan

1. Add explicit candidate-panel management in `IMEHostCore`
2. Keep bridge-backed composition and candidate data as the single source of truth
3. Rebuild `SmartIMEHost`
4. Manually verify candidate visibility, commit, and cancel behavior in a standard macOS text client
5. Record the observed result in local docs and task status

## Open Questions

- Whether `IMKCandidates` needs additional styling or positioning tweaks after the first visible loop is working
- Whether any remaining input-client-specific quirks require follow-up behavior after TextEdit-level validation
