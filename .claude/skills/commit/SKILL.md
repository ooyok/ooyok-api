---
name: commit
description: Write and create a git commit using Conventional Commits (feat, fix, docs, …). Use when the user asks to commit, write a commit message, or save changes to git.
---

# Commit

## General Rule
- Be concise, just add the key points
- Before each commit ask user permission

## Steps
1. Run `git status` and `git diff` (staged and unstaged) to see what changed.
2. Stage only the files that belong to this change. If unrelated changes are mixed in, propose splitting them into separate commits.
3. Draft the message in the format below.
4. Show the user the files to be committed and the full message, and ask for permission.
5. Commit only after the user approves. If they ask for edits, revise and ask again.

## Format

```
<type>(<scope>): <subject>

<body: why this change, 1–2 lines>

- <key change>
- <key change>
```

- `scope` is optional: the area touched (e.g. `auth`, `routines`, `infra`, `harness`).
- Subject: imperative mood, lowercase, no trailing period, ≤ 72 characters.
- Body and bullets are optional for trivial changes.

## Titles
- `feat` — Introduce a new feature
- `fix` — Fix a bug
- `refactor` — Restructure code without changing behavior
- `perf` — Improve performance
- `docs` — Documentation changes
- `style` — Formatting changes without affecting logic
- `test` — Add or modify tests
- `build` — Build system or dependency changes
- `ci` — CI/CD configuration changes
- `chore` — Routine maintenance
- `revert` — Revert a previous commit

## Examples

```
feat(auth): add Google OAuth authentication

Implement Google OAuth login to simplify account creation
and eliminate the need for password management.

- Add Google OAuth authorization flow
- Exchange authorization codes through the backend
- Store refresh tokens securely on the server
- Add authentication middleware for protected routes
```
