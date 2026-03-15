## Context

The repository now has a working macOS InputMethodKit host target, but the host still uses placeholder session behavior. The technical design already chose `librime` as the Chinese input core, so the next narrow milestone is to integrate a real bridge that can initialize the engine, create a session, process key events, and surface composition/candidate/commit results back to the host.

This change remains deliberately narrow. It does not attempt to implement English input, mixed-mode routing, schema management UI, candidate paging shortcuts, or Companion integration. It focuses only on the minimum `librime` path needed to prove that the project can perform real Chinese input through the host shell.

## Goals / Non-Goals

**Goals:**

- Add a first `rime-bridge` package that wraps the minimum `librime` runtime and session APIs needed by the host
- Replace the host placeholder composition logic with bridge-backed Chinese session updates
- Preserve the existing host boundary so later English and routing changes can plug in without rewriting the outer IME control flow
- Document the local `librime` dependency path used for development validation

**Non-Goals:**

- Implement English completion or correction
- Implement full Chinese/English mode routing
- Add schema switching UI or user configuration surfaces
- Implement candidate page navigation or number-key candidate selection beyond what is required to prove the bridge works
- Vendor and build `librime` from source inside the repository in this milestone

## Decisions

### Use a project-owned Swift wrapper around the C API

The bridge should expose small Swift-native types and operations while keeping raw C API handling in one module. This gives the IME host a stable boundary and avoids leaking `RimeContext`, `RimeCommit`, or memory-management details into host code.

Alternative considered:

- Call `librime` C APIs directly from `IMEHostCore`
  - Rejected because it would couple InputMethodKit controller code to foreign-memory lifecycle and make later engine substitution harder.

### Keep the first bridge limited to a single Chinese session path

The first bridge should only support the core path:

- initialize runtime
- create session
- process key
- read commit/context/status
- reset and destroy session

Anything beyond that, such as schema switching, paging helpers, or advanced notifications, can wait until the base path is proven.

Alternative considered:

- Integrate schema selection, candidate paging, and notification handlers immediately
  - Rejected because it would expand the milestone before the core runtime path is validated.

### Prefer local development linkage over vendoring `librime` build logic now

`librime` already supports macOS installation through Homebrew and manual builds. The first bridge milestone should link against an installed local `librime` and document that expectation rather than trying to absorb `librime`'s full build system into this repository immediately.

Alternative considered:

- Vendor and build `librime` entirely from `third_party/librime-src`
  - Rejected for this milestone because it would mix bridge work with third-party build orchestration risk.

### Introduce an explicit Chinese engine boundary in the host

The host should stop owning placeholder composition logic directly. Instead, it should delegate Chinese input updates through a small engine-facing protocol implemented by the `rime-bridge` package. This keeps the host architecture aligned with the project design and prepares for later English routing.

Alternative considered:

- Keep `IMEHostSessionStore` as the primary Chinese logic owner and call `librime` from inside it
  - Rejected because it would preserve the wrong abstraction boundary and make future routing work harder.

## Bridge Shape

The first bridge can stay small. A single runtime object should own `librime` initialization, session lifecycle, and API calls. The host should receive a Swift-native session update object containing:

- composition text
- candidates
- optional commit text
- status fields needed for the host milestone

This change may reuse `CompositionState` and `Candidate`, but the bridge should be free to define an internal mapping layer so host-facing models remain independent from raw `librime` structures.

## Host Integration Strategy

The host currently uses `IMEHostSessionStore` with placeholder candidates. After this change:

1. the IME controller forwards supported key events to the Chinese engine boundary
2. the `rime-bridge` processes the event through an active session
3. the host updates composition/candidate UI from the returned session update
4. any commit text emitted by `librime` is inserted into the focused client

The host should still keep the outer InputMethodKit lifecycle and commit routing. The bridge should not own AppKit or InputMethodKit concerns.

## Risks / Trade-offs

- [`librime` local installation differs across machines] -> Document a single supported local validation path first and keep the bridge code independent from installation method.
- [Bridge memory handling is easy to get wrong] -> Keep all `RimeContext` / `RimeCommit` allocation and free logic isolated in one package with narrow mapping helpers.
- [The host boundary becomes overfit to `librime`] -> Use project-owned session update models instead of exposing raw C structs.
- [This change only supports Chinese mode] -> Acceptable for this milestone because English routing is a later change and should build on a proven Chinese path.

## Migration Plan

1. Create the `rime-bridge` package and add minimal build wiring.
2. Add the Swift wrapper around the required `librime` runtime and session APIs.
3. Replace placeholder Chinese session handling in the host with bridge-backed updates.
4. Document the local `librime` installation and validation workflow.
5. Verify the IME host still builds and can exercise real Chinese composition through the bridge.

No user-data migration is required because the current implementation only contains placeholder host behavior.

## Open Questions

- Which local `librime` installation path should the repository standardize for day-to-day development: Homebrew, manual local build, or both?
- Does the first bridge milestone need to support candidate selection from the host immediately, or is composition plus commit validation sufficient?
- Should the bridge cache status fields such as `is_ascii_mode` now, or can that wait until explicit mode routing work begins?
