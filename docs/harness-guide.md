# Harness Guide

The "harness" is everything around the code that keeps development fast and safe: rules for Claude Code, automated hooks, skills, local tooling, git hooks, and CI. This page records **what exists, what each piece is for, and how to change it**.

> **Keep this page current.** Any change to `CLAUDE.md`, `.claude/`, `.pre-commit-config.yaml`, `justfile`, `pyproject.toml` tool config, or `.github/` must update the status table in the same PR. (CLAUDE.md tells Claude to do this.)

## Status

Legend: ✅ in place · 🟡 partial · ⬜ planned

Last updated: 2026-10-30. Docs are written; no harness pieces are implemented yet.

| # | Piece | Location | Status | Purpose |
|---|---|---|---|---|
| 1 | Project rules for Claude | `CLAUDE.md` | ✅ | conventions, commands, layering, TDD, never-do list |
| 2 | Docs | `docs/` | ✅ | PRD, architecture, GCP setup, testing, this guide, ADRs |
| 3 | Python project + tool config | `pyproject.toml`, `uv.lock`, `.python-version` | ⬜ | dependencies; ruff, mypy, pytest, coverage config |
| 4 | Task runner | `justfile` | ⬜ | one name per common command (`just test`, `just dev`) |
| 5 | Local stack | `docker-compose.yml` | ⬜ | Postgres, Redis, Pub/Sub emulator, Firebase Auth emulator |
| 6 | Git hooks | `.pre-commit-config.yaml` | ⬜ | format, lint, types, secrets before commit; unit tests before push |
| 7 | Claude permissions | `.claude/settings.json` | ⬜ | auto-allow safe commands, block dangerous ones |
| 8 | Hook: format on edit | `.claude/hooks/format.sh` | ⬜ | ruff format + fix on each edited `.py` file |
| 9 | Hook: protect files | `.claude/hooks/guard.sh` | ⬜ | block edits to `.env*` and merged migrations |
| 10 | Hook: test gate on stop | `.claude/hooks/test-gate.sh` | ⬜ | unit tests + mypy must pass before Claude ends a turn |
| 11 | Skill: new endpoint | `.claude/skills/new-endpoint/SKILL.md` | ⬜ | TDD recipe for adding an endpoint |
| 12 | Skill: DB migration | `.claude/skills/db-migration/SKILL.md` | ⬜ | create + safety-review an Alembic migration |
| 13 | Skill: release | `.claude/skills/release/SKILL.md` | ⬜ | pre-deploy / promote checklist |
| 14 | MCP: local Postgres (optional) | `.mcp.json` | ⬜ | read-only queries against the **local** dev DB |
| 15 | CI | `.github/workflows/ci.yml` | ⬜ | lint, types, tests, security scans on every PR |
| 16 | Deploy | `.github/workflows/deploy.yml`, `promote.yml` | ⬜ | build → staging; manual promote → prod |
| 17 | Dependency updates | `.github/dependabot.yml` | ⬜ | weekly PRs for pip + GitHub Actions |
| 18 | Editor | `.editorconfig`, `.vscode/extensions.json`, `.vscode/settings.json` | ⬜ | consistent formatting, recommended extensions |

---

## 1. CLAUDE.md

Loaded into every Claude Code session in this repo. Kept short and rule-shaped; details live in `docs/` and are linked. Edit it when a convention changes or Claude keeps repeating a mistake.

## 3. Python tooling (front-end equivalents)

| Front end | Here | Config |
|---|---|---|
| npm / pnpm | **uv** | `pyproject.toml`, `uv.lock` |
| ESLint + Prettier | **Ruff** (lint + format + import sort) | `[tool.ruff]` |
| `tsc` | **mypy --strict** (+ pydantic plugin) | `[tool.mypy]` |
| Jest/Vitest | **pytest** | `[tool.pytest.ini_options]` |
| Husky + lint-staged | **pre-commit** | `.pre-commit-config.yaml` |
| npm scripts | **just** | `justfile` |

Planned Ruff rule sets: `E, F, W, I, B, UP, SIM, ASYNC, S (bandit), N, RUF`, line length 100.

## 4. justfile

Planned recipes:

| Recipe | Does |
|---|---|
| `just setup` | `uv sync`, `pre-commit install --install-hooks` |
| `just dev` | `docker compose up -d` + `uvicorn --reload` |
| `just test` / `test-unit` / `test-cov` | test layers (see testing-guide) |
| `just lint` | `ruff check` + `ruff format --check` + `mypy` |
| `just fix` | `ruff check --fix` + `ruff format` |
| `just migrate` / `just migration name=...` | `alembic upgrade head` / `alembic revision --autogenerate` |
| `just openapi` | export `openapi.json` snapshot |
| `just smoke URL=...` | smoke tests against a deployed env |

## 6. Git hooks (pre-commit)

| Stage | Hooks |
|---|---|
| commit | `ruff check --fix`, `ruff format`, `mypy`, `gitleaks`, `check-yaml`, `check-toml`, `end-of-file-fixer`, `trailing-whitespace`, `uv lock --check` |
| push | `just test-unit` |

Install: `just setup`. Skip in an emergency with `--no-verify` (CI still enforces everything).

## 7. Claude permissions (`.claude/settings.json`)

Planned shape:

```json
{
  "permissions": {
    "allow": [
      "Bash(uv run pytest:*)", "Bash(uv run ruff:*)", "Bash(uv run mypy:*)",
      "Bash(uv run alembic:*)", "Bash(just:*)", "Bash(docker compose:*)",
      "Bash(terraform plan:*)", "Bash(terraform fmt:*)", "Bash(terraform validate:*)"
    ],
    "deny": [
      "Bash(terraform apply:*)", "Bash(terraform destroy:*)",
      "Bash(gcloud * delete:*)", "Bash(git push --force:*)",
      "Read(.env*)", "Read(**/*.tfstate)"
    ]
  }
}
```

Why: Claude can run the TDD loop without prompting, but anything that changes cloud resources or reads secrets needs a human.

## 8–10. Claude Code hooks

Configured under `"hooks"` in `.claude/settings.json`; scripts live in `.claude/hooks/`.

| Hook | Event / matcher | Behaviour | Why |
|---|---|---|---|
| `format.sh` | `PostToolUse`, `Edit\|Write` | if the edited file is `*.py`: `ruff format` + `ruff check --fix` on that file | code is always formatted; diffs stay clean |
| `guard.sh` | `PreToolUse`, `Edit\|Write` | exit 2 (block) if the path matches `.env*`, `*.tfstate`, or a migration file already on `origin/main` | secrets never touched; applied migrations are immutable |
| `test-gate.sh` | `Stop` | run `just test-unit` + `mypy`; on failure print the output to stderr and exit 2 so Claude keeps working. Skips if the input has `stop_hook_active: true` to avoid loops | enforces TDD green before a turn ends |

The Stop gate runs only fast unit tests; integration and API tests run via `just test` and CI.

## 11–13. Skills

| Skill | Trigger | Steps |
|---|---|---|
| `new-endpoint` | "add an endpoint for …" | 1) write API test (red) → 2) request/response schemas → 3) service unit tests + service → 4) repository + integration test → 5) router → 6) migration if needed → 7) update OpenAPI snapshot, PRD endpoint table |
| `db-migration` | "add a column/table …" | autogenerate → review checklist: backward compatible (expand/contract), no table-rewriting `ALTER` on big tables, indexes `CONCURRENTLY`, data migrations separate, downgrade defined → run upgrade/downgrade locally |
| `release` | "prepare a release / promote" | CI green on SHA → migration reviewed → staging smoke passed → changelog → run `promote.yml` |

Built-in commands to use as well: `/code-review` before opening a PR, `/security-review` for auth, data-access, or infra changes.

## 14. MCP

Kept minimal on purpose: `gh` and `gcloud` CLIs cover GitHub and GCP.

Optional: a Postgres MCP server pointed **only** at the local Docker Compose database with a read-only role. Never configure it with staging or prod credentials.

## 15–17. CI/CD

See [architecture-infra-guide.md §13](architecture-infra-guide.md#13-cicd) for the pipeline design and [testing-guide.md](testing-guide.md#ci-gates) for the merge gates.

## Changing the harness

1. Make the change.
2. Update the row in the status table (and the section below it if behaviour changed).
3. If it changes a rule Claude must follow, update `CLAUDE.md`.
