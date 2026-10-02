# Git Workflow

## Branching

- Default branch: `main`
- For normal development, create short-lived feature branches only when parallel work or review isolation is useful.
- Branch naming:
  - `feat/<topic>`
  - `fix/<topic>`
  - `docs/<topic>`
  - `chore/<topic>`

## Commits

- Keep each commit focused on one logical change.
- Prefer small, reviewable commits over large checkpoint commits.
- Commit message format:

```text
<type>: <summary>
```

Examples:

```text
feat: add initial IME host skeleton
fix: guard clipboard transform against empty text
docs: update technical design for context policy
chore: initialize project workspace
```

Recommended types:

- `feat`
- `fix`
- `docs`
- `refactor`
- `test`
- `chore`

## Staging Rules

- Stage only files directly related to the task.
- Do not mix architecture doc updates with unrelated code changes unless the code depends on those docs.
- Do not commit generated files unless the repository explicitly tracks them.

## Pull Request Expectations

- State what changed.
- State why it changed.
- State any follow-up or known gaps.
- Link to the relevant Notion page or task when applicable.

## Protected Behaviors For Agents

- Do not force-push.
- Do not amend published commits.
- Do not rebase away other people's work unless explicitly requested.
- Do not commit secrets, tokens, or private local configuration.
- Do not bypass the local docs. Read `project-brief.md`, `technical-design.md`, and `implementation-log.md` before changing code.

## Documentation Sync Rules

- If implementation changes architecture or interfaces, update `docs/technical-design.md`.
- If implementation changes project direction or scope, update Notion.
- After each meaningful coding session, append a factual entry to `docs/implementation-log.md`.
