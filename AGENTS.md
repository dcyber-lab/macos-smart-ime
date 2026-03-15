# Project Instructions

This directory contains the `macos-smart-ime` project. Treat the files in `docs/` as the local source of truth for implementation decisions.

## Required Read Order

Before making code changes, read:
1. `docs/project-brief.md`
2. `docs/technical-design.md`
3. `docs/openspec-workflow.md`
4. `docs/implementation-log.md`

## Coding Rules

- Keep the architecture split between `IME`, `Companion`, and shared packages.
- Do not put AI, network calls, or long-running text cleaning in the IME real-time input path.
- Use `librime` as the Chinese input core instead of reimplementing Chinese input logic.
- Keep English completion/correction logic in project-owned modules.
- Treat password fields, secure text fields, OTP fields, and other sensitive input as no-context zones.
- For every new feature, create or update an OpenSpec change before implementation.
- Do not start implementation for a new feature until `openspec/changes/<change-name>/` contains the required proposal, design, and tasks artifacts.
- Use OpenSpec workflows as the first step:
  - `/opsx:propose` or `openspec-propose` to define a new feature
  - `/opsx:explore` to refine artifacts
  - `/opsx:apply` or `openspec-apply-change` only after the change is implementation-ready

## Documentation Sync

When code changes are made:
1. Update `docs/implementation-log.md` with what changed, why, and any follow-up work.
2. If the implementation changes architecture, interfaces, or module boundaries, update `docs/technical-design.md`.
3. If a milestone or task meaningfully advances, sync the corresponding task/page in Notion.
4. If the change came through OpenSpec, keep the related artifacts in `openspec/changes/` aligned with the implementation state.

## Git Workflow

- Work on the default branch `main` unless a task explicitly requires a feature branch.
- Keep commits focused and small enough to explain in one sentence.
- Use imperative commit subjects, for example: `Add IME session model`.
- Before committing, review the diff and avoid bundling unrelated document or code changes together.
- Do not rewrite published history unless explicitly requested.
- Do not force-push unless explicitly requested.
- Keep local docs and Notion in sync with meaningful implementation changes.
- If a task changes project scope, architecture, or milestones, update docs before or alongside the code commit.

## Commit Checklist

Before creating a commit:
1. Read `docs/project-brief.md`, `docs/technical-design.md`, `docs/openspec-workflow.md`, and `docs/implementation-log.md`.
2. If this is a new feature, confirm an OpenSpec change exists and is ready for implementation.
3. Confirm the change stays within the IME/Companion/shared-module boundary.
4. Update docs if interfaces, architecture, or milestones changed.
5. Stage only relevant files.
6. Write a commit message that describes the actual change.

## Notion Sync Targets

- Project page: `<removed>`
- Design doc: `<removed>`
- Task database: `<removed>`

## Preferred Project Layout

- `apps/ime`
- `apps/companion`
- `packages/rime-bridge`
- `packages/english-engine`
- `packages/transform-engine`
- `packages/shared-models`
- `packages/user-data`
- `third_party/librime`

## Agent Behavior

- Prefer local-first changes and commit them before attempting remote integration work.
- When creating code, follow the current design docs rather than inventing a parallel architecture.
- After completing a meaningful unit of work, append a short factual note to `docs/implementation-log.md`.
- Treat OpenSpec as the default planning workflow for new features in this repository.
- For new feature requests, propose first and implement second.
