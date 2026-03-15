# Design

## Context

The repository already has:

- a working `SmartIMEHost` app target
- a `librime` bridge that can process Chinese key events
- an installable and selectable macOS input source

What is still missing is the first complete user interaction loop for Chinese candidate acceptance.

## Scope

This change only covers:

- `Space` to commit the first candidate
- number-key candidate selection
- `Escape` to clear composition

The change remains inside the current `IMEHostCore` and `rime-bridge` boundaries.

## Decisions

### Let `librime` remain the source of truth

Candidate acceptance should continue to flow through `librime` key processing where possible. The IME host should not create a parallel candidate-selection implementation that bypasses the bridge state model.

For this milestone, this means the host forwards raw key events for `Space` and digit keys into the Chinese engine and relies on `librime` to decide whether those keys commit a candidate. The host does not call a separate candidate-selection API and does not maintain its own candidate cursor.

### Add only minimal host-side behavior

The host should only add behavior needed to:

- suppress normal text insertion when the IME consumes the event
- clear local session state when `Escape` cancels composition
- map candidate arrays and composition updates to the existing session store

### Keep paging out of scope

Paging is intentionally deferred. The first usability milestone is simply selecting from the current visible candidates.

For this change, "visible candidates" means the current ordered candidate list surfaced through `CompositionState.candidates`. The host does not attempt to infer or control a separate pagination state.

## Proposed Implementation

### IME host behavior

Update `IMEInputController` so that:

- `Space` is forwarded into the Chinese engine when composition is active and any commit remains engine-driven
- digit keys are forwarded into the engine for candidate selection when composition is active and any commit remains engine-driven
- `Escape` clears the engine session and local composition state when composition exists

### Session state behavior

The current `IMEHostSessionStore` can remain simple for this milestone. It only needs to:

- hold the latest composition and candidate list
- reset cleanly after commit or cancel

### Verification

Manual verification for this milestone should confirm:

1. typing a simple pinyin sequence shows candidates
2. pressing `Space` commits the first candidate
3. pressing `1` or another visible candidate number commits that candidate
4. pressing `Escape` clears composition without committing text
5. the host does not leak raw `Space`, digit, or `Escape` keystrokes into the client when the IME consumes them

## Risks

- `librime` schema defaults may treat some space or digit behavior differently than expected
- candidate numbering may differ from assumptions in the host UI

These are acceptable risks for this milestone because the change is small and easy to observe manually.
