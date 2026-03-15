# OpenSpec Workflow

## Rule

For any new feature in this repository, do not start implementation immediately.

Create or update an OpenSpec change first, then implement only after the change is ready.

## Minimum Required Flow

1. Propose the change.
2. Review the generated artifacts.
3. Refine proposal, design, and tasks as needed.
4. Start implementation only when the change is implementation-ready.
5. Keep the tasks and local docs aligned while coding.

## Where OpenSpec Lives

- Change proposals: `openspec/changes/<change-name>/`
- Main specs: `openspec/specs/`

## Preferred Commands

### Start a new feature

```bash
/opsx:propose "describe the feature"
```

Or, with the CLI-based workflow:

```bash
openspec new change "<change-name>"
```

### Refine or inspect

```bash
/opsx:explore
openspec list
openspec status --change "<change-name>"
```

### Implement

```bash
/opsx:apply
```

Only use apply after the change has the required artifacts.

## Artifact Expectation

For a new feature, the change should normally include:

- `proposal.md`
- `design.md`
- `tasks.md`

## Agent Policy

- For new features, propose first and implement second.
- For small bug fixes or trivial documentation edits, OpenSpec is optional unless the change materially affects behavior or architecture.
- If implementation changes the design, update both the OpenSpec artifacts and local docs.
- After implementation, record the result in `docs/implementation-log.md` and sync Notion if the milestone or design meaningfully changed.

