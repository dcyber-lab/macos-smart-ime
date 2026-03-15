## 1. IME Host Bootstrap

- [x] 1.1 Create the initial `apps/ime` project structure for the macOS input method host
- [ ] 1.2 Add the minimum InputMethodKit host entrypoints and target wiring required to build the IME shell
- [x] 1.3 Document the local bootstrap assumptions needed to validate the host on macOS

## 2. Session Model

- [x] 2.1 Add shared session types for composition state and candidate state under `packages/shared-models`
- [x] 2.2 Add a minimal host-side session store that can update composition and placeholder candidates

## 3. Input And Commit Flow

- [x] 3.1 Implement a minimal input controller path that receives supported key input
- [x] 3.2 Implement a deterministic commit path that inserts test text into the focused client
- [x] 3.3 Connect the input controller to the session store so state transitions are explicit

## 4. Validation And Documentation

- [x] 4.1 Verify the project layout and documentation match the IME host boundary introduced in this change
- [x] 4.2 Update implementation notes and local docs to reflect the host bootstrap milestone
