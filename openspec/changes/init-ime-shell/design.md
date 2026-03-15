## Context

The repository currently contains only project structure, docs, and workflow rules. The first implementation milestone is to prove that a macOS InputMethodKit host can be built, enabled, receive input events, maintain a minimal input session, and commit text back to the focused client.

This change is intentionally narrow. It creates the IME host shell that later `librime`, English completion, and Companion features will depend on. The design must preserve a clean boundary between the IME host and future input engines.

## Goals / Non-Goals

**Goals:**
- Create the first runnable IME target under `apps/ime`
- Define the minimum host-side session model for composition and candidates
- Prove an end-to-end path from key event to committed text
- Keep the host boundary small enough that `librime` and future engines can plug in later

**Non-Goals:**
- Integrate `librime`
- Implement real Chinese input or English completion
- Build the Companion app
- Add network access, AI logic, or long-running processing
- Build a production-grade candidate UI

## Decisions

### Use InputMethodKit as the first milestone boundary

The host shell will be built directly on `InputMethodKit` because the project must validate the real macOS IME lifecycle early. Deferring this would push the highest-risk integration point later in the roadmap.

Alternative considered:
- Build shared models or engine stubs first without a runnable IME host
  - Rejected because it would not prove installation, activation, or input-client integration.

### Keep engine logic out of the host milestone

The IME target will own lifecycle, input handling entrypoints, session state, and commit routing. It will not own Chinese parsing or advanced suggestion logic yet.

Alternative considered:
- Start integrating `librime` in the same change
  - Rejected because it would mix host-risk and engine-risk in one milestone, making failures harder to isolate.

### Introduce a minimal shared session model now

This change will add shared types for composition state and candidate lists so the host can evolve toward engine-backed behavior without rewriting the outer control flow.

Alternative considered:
- Hardcode all state inside the IME controller
  - Rejected because it would create avoidable coupling before `rime-bridge` and `english-engine` land.

### Use a stub candidate/update flow for validation

The first host milestone will allow simple composition updates and a deterministic commit path using placeholder behavior. This is enough to verify the IME shell before real engine integration.

Alternative considered:
- Skip candidates entirely in the first milestone
  - Rejected because the project needs to validate session state transitions, not just raw text insertion.

## Risks / Trade-offs

- [InputMethodKit integration differs from assumptions] -> Validate the host with the narrowest possible feature set first and keep engine integration out of this change.
- [Stub session logic becomes accidental production logic] -> Keep the stub behavior explicit and isolate it behind host/session types that will later delegate to real engines.
- [Candidate handling is too shallow to support next milestones] -> Model candidate state now even if the first implementation uses placeholder data.
- [Environment setup takes longer than expected] -> Treat successful target creation and activation as milestone success even before richer input behavior exists.

## Migration Plan

1. Create the IME host target and minimal structure under `apps/ime`.
2. Add the shared session types required for composition and candidate state.
3. Implement a minimal controller path that receives key input and commits deterministic test text.
4. Verify the input method can be enabled and exercised locally.
5. Keep the host boundary ready for the next change, which will integrate `librime`.

No rollback or migration of existing runtime behavior is required because this is the first implementation milestone.

## Open Questions

- Which exact Xcode project structure is most maintainable for `apps/ime` in this repository?
- How much of the candidate UI can be validated with placeholder behavior before `librime` integration is necessary?
- Should the first host milestone include minimal logging hooks for debugging session lifecycle?
