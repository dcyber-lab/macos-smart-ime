# Project Brief

## Goal

Build a macOS intelligent input system for knowledge workers with a focus on:

- Chinese input
- English completion
- Chinese-English correction
- Trusted clipboard workflows
- One-key English transformation
- Screenshots with markup, pinning, and on-device text recognition from a system hotkey (added 2026-10-05)
- A local intelligence hub: learn from what the user commits, on this Mac only, and offer help (better candidates, Chinese-English rewriting, calendar reminders, quick phrases) that the user confirms with a key. See `docs/intelligence-hub.md`.

## Product Positioning

This is not just a Chinese input method. The intended product value is the combined experience of:

- Chinese input powered by `librime`
- Project-owned English completion and correction
- Companion-driven clipboard and command workflows

## MVP Scope

1. Chinese and English input
2. English completion
3. Chinese-English correction
4. Trusted clipboard
5. One-key English transformation

## Non-Goals For Early Milestones

- AI inside the IME real-time path
- Long-running text cleaning during key-by-key input
- Full-document context grabbing as a hard dependency
- Cloud-dependent core typing features
- Sending learned or typed content off the Mac, or acting on it without the user's confirmation (decided 2026-10-01)

## Delivery Workflow

- Keep implementation, local docs, and Notion aligned after the work lands.
