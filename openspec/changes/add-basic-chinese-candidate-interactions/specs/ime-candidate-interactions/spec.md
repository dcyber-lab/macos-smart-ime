# IME Candidate Interactions Spec

## Requirements

### Requirement: Space accepts the first visible Chinese candidate

When the current IME session has an active Chinese composition and visible candidates, pressing `Space` must commit the first visible candidate instead of inserting a literal space into the client text field. For this milestone, "visible candidates" means the candidate list currently surfaced by the Chinese engine in `CompositionState.candidates`.

### Requirement: Number keys can select visible Chinese candidates

When the current IME session has visible Chinese candidates, pressing a visible candidate number key must commit the corresponding candidate through the current Chinese engine path. In this milestone the host forwards the raw key event and relies on `librime` to perform the selection.

### Requirement: Escape clears Chinese composition

When the current IME session has an active Chinese composition, pressing `Escape` must cancel the composition and clear the current local candidate state without committing text.
