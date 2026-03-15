## Context

The project has already proven three important steps:

- a real `SmartIMEHost` macOS app target exists
- the host compiles through `xcodebuild`
- Chinese composition is delegated through the project-owned `rime-bridge`

What is still missing is the operational path from repository checkout to system-level validation. Right now the repository documents the build step and mentions `/Library/Input Methods/`, but it does not provide a deterministic install path, an uninstall path, or a single manual validation checklist that future contributors can follow.

This change stays focused on installability and manual validation. It does not add new typing features beyond what is necessary to confirm the current Chinese path works in a real text client.

## Goals / Non-Goals

**Goals:**

- Add a repeatable local build-and-install workflow for `SmartIMEHost`
- Minimize ad hoc shell commands by providing repository-owned install scripts
- Add a manual validation checklist that confirms:
  - the input method is installed
  - macOS can expose it as an input source
  - the host can be selected and used in a normal text field
  - basic Chinese composition and commit behavior work through the current `librime` bridge
- Keep the workflow aligned with OpenSpec, local docs, and future agent usage

**Non-Goals:**

- Add candidate paging, number-key candidate selection, or English mode work
- Add code-signing automation for distribution or release builds
- Add CI support for GUI validation
- Add packaging or notarization

## Decisions

### Use repository-owned shell scripts for local installation

The install flow should be captured in small repository-owned shell scripts instead of remaining as a prose-only sequence. This makes the workflow reproducible for both humans and other agents.

Alternative considered:

- Keep the flow entirely in README instructions
  - Rejected because it leads to command drift and repeated manual mistakes.

### Build into a predictable derived data path

The install script should build `SmartIMEHost` into a deterministic local build directory instead of relying on whatever DerivedData path Xcode chooses at runtime. This makes it easier to locate the app bundle for install, uninstall, and troubleshooting.

Alternative considered:

- Keep using a generic DerivedData example path in documentation
  - Rejected because it is inconvenient for scripting and fragile for repeated validation.

### Default to a user-local install path

The local validation workflow should default to `~/Library/Input Methods/` and support an explicit system-wide install mode for `/Library/Input Methods/`. This keeps the common validation path usable without administrator privileges while still allowing a system-wide install when needed.

Alternative considered:

- Only support `/Library/Input Methods/`
  - Rejected because it adds avoidable friction to the common local validation path.

### Separate install/uninstall from validation checklist

The scripts should focus on build/install lifecycle, while the validation checklist should clearly describe the manual GUI steps and expected outcomes. This keeps system-privileged operations small and makes validation evidence easier to reason about.

Alternative considered:

- Hide all validation behind one large script
  - Rejected because enabling the input source and checking behavior still requires user-observable GUI steps.

### Keep validation scope at “basic Chinese input”

For this milestone, “basic Chinese input” means:

- the IME appears as an input source after installation
- the user can switch to it
- a simple pinyin sequence produces composition and candidates
- committing the candidate inserts Chinese text into a text client

This is enough to prove the installed app and the current `librime` bridge work together in a real environment.

Alternative considered:

- Expand the validation milestone to include richer interaction behaviors
  - Rejected because installation risk and feature risk should remain separated.

## Proposed Implementation

### Scripts

Add a small `scripts/ime/` workflow:

- `build-host.sh`
  - generate the Xcode project if needed
  - build `SmartIMEHost`
  - place the app bundle in a deterministic local output path
- `install-host.sh`
  - install into `~/Library/Input Methods/` by default
  - support an explicit system-wide mode for `/Library/Input Methods/`
  - register or refresh local visibility where practical
- `uninstall-host.sh`
  - remove the installed app bundle from the selected install location

These scripts should stay narrow and explicit. They should fail fast and print the exact app path they are operating on.

### Documentation

Add a dedicated manual validation document that covers:

- prerequisites
- build step
- install step
- how to enable the input source in macOS
- a basic validation checklist
- how to remove or refresh the install

Update existing README material to point at the new workflow instead of duplicating partial instructions.

## Risks / Trade-offs

- [Install requires privileged filesystem access] -> Keep privileged commands in one narrow script and call that script explicitly when needed.
- [The GUI enablement path differs slightly across macOS versions] -> Document the current path at a high level and keep the validation checklist focused on observable outcomes.
- [An unsigned local build may behave differently from a fully signed product build] -> Acceptable for this milestone because the goal is local system validation, not distribution.
- [The build script may drift from project settings] -> Generate the Xcode project as part of the scripted workflow and keep build output paths deterministic.

## Migration Plan

1. Add install/uninstall scripts under a repository-owned scripts path.
2. Update documentation to point to the scripted workflow.
3. Run the local build/install workflow and verify the app still builds.
4. Perform or document the manual validation checklist for the current Chinese path.
5. Record the result in local docs and task tracking.

No product data migration is required for this change.

## Open Questions

- Should the install script also restart any user-facing macOS services, or should that remain a manual post-install step?
- Do we want the validation document to capture expected sample inputs and outputs now, or keep it at the checklist level until candidate-selection behavior is richer?
