## 1. Bridge Package Bootstrap

- [x] 1.1 Create the initial `packages/rime-bridge` target structure and build wiring for a Swift-facing `librime` bridge
- [x] 1.2 Document the local `librime` dependency path used for development validation

## 2. Bridge Runtime And Session Mapping

- [x] 2.1 Add a bridge runtime object that initializes and finalizes `librime` with project-local trait configuration
- [x] 2.2 Add session lifecycle support for create, reset, and destroy
- [x] 2.3 Map `librime` composition, candidate, and commit outputs into project-owned session update models

## 3. Host Integration

- [x] 3.1 Introduce a host-side Chinese engine boundary so InputMethodKit code no longer owns placeholder Chinese logic directly
- [x] 3.2 Route supported key input through the `rime-bridge` and update host composition/candidate state from returned bridge updates
- [x] 3.3 Commit `librime` output text into the focused client when the bridge emits a commit

## 4. Validation And Documentation

- [x] 4.1 Verify the host and bridge build together through the local Xcode workflow
- [x] 4.2 Update implementation notes and local docs to reflect the new `librime` bridge boundary
