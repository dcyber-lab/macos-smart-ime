# Technical Design

## Architecture

### IME

Owns the real-time typing path:

- key handling
- composition
- candidates
- commit
- input mode switching
- English completion
- lightweight Chinese-English correction

### Companion App

Owns explicit and async workflows:

- global hotkeys
- clipboard read/write
- one-key English transformation
- future AI and text cleaning commands
- settings, logs, and permissions

### Shared Packages

- `rime-bridge`
- `english-engine`
- `transform-engine`
- `shared-models`
- `user-data`

## Technology Choices

- Chinese input core: `librime`
- macOS IME frontend: `InputMethodKit`
- Companion: menu bar macOS app
- English logic: project-owned engine
- Command-style transformations: `transform-engine`

## Data and Privacy Boundaries

- Sensitive fields must not use context enhancement.
- Password, secure text, and OTP-like fields are no-context zones.
- Default processing is local.
- Any future AI processing must be explicit and must stay outside the IME real-time path.

## Context Strategy

### Level 1

IME-owned context:

- current composition
- current candidates
- recent committed text

### Level 2

Local neighboring text only when available:

- small window around cursor
- no full-document assumption

### Level 3

Explicit Companion-driven analysis:

- clipboard text
- selected text
- sentence or paragraph level operations

## Planned Repository Layout

```text
apps/
  ime/
  companion/

packages/
  rime-bridge/
  english-engine/
  transform-engine/
  shared-models/
  user-data/

third_party/
  librime/
```

## Initial Interfaces

```swift
struct Candidate {
    let text: String
    let source: CandidateSource
    let score: Double
}

enum InputMode {
    case chinese
    case english
    case mixed
}

struct CompositionState {
    var rawInput: String
    var mode: InputMode
    var composition: String
    var candidates: [Candidate]
    var recentText: String
}
```

```swift
protocol InputSessionHandler {
    func handle(event: KeyEvent) -> SessionUpdate
}

protocol ChineseInputEngine {
    func process(_ event: KeyEvent) -> SessionUpdate
    func reset()
}

protocol EnglishInputEngine {
    func process(_ event: KeyEvent, context: LocalContext) -> SessionUpdate
}

protocol ClipboardTransforming {
    func run(command: TransformCommand) async throws
}
```

## Phase 1 Acceptance

1. The macOS input method can be installed and enabled.
2. Chinese input works through `librime`.
3. English mode accepts normal typing.
4. English completion can produce candidates.
5. Basic English correction works at word boundaries.
6. Companion can read clipboard text and write back transformed text.

