# ooyok-api

The API layer for ooyok: a simplified, Hevy-inspired workout logger, built to pivot toward rehabilitation.

**Status:** planning complete, scaffold not yet built (milestone M0). See [docs/PRD.md](docs/PRD.md#milestones).

## Stack

Python 3.14 · FastAPI · Pydantic v2 · SQLAlchemy 2 (async) · Alembic · PostgreSQL (Cloud SQL) · Redis · Pub/Sub · Firebase Authentication · Cloud Run (`asia-east1`) · Terraform · GitHub Actions

## Quickstart

> These commands work once M0 is in place.

Prerequisites: [uv](https://docs.astral.sh/uv/), [just](https://just.systems/), Docker.

```bash
git clone git@github.com:ooyok/ooyok-api.git
cd ooyok-api
just setup      # install deps + git hooks
just dev        # start Postgres, Redis, emulators; run API with reload
just test       # run the test suite
```

API at http://localhost:8000, interactive docs at http://localhost:8000/docs.

## Development

| Need | Tool | Command |
|---|---|---|
| Dependencies / venv | uv | `uv sync`, `uv add <pkg>` |
| Lint + format (ESLint + Prettier equivalent) | Ruff | `just lint`, `just fix` |
| Type checking (`tsc` equivalent) | mypy (strict) | `just lint` |
| Tests | pytest | `just test`, `just test-unit` |
| Git hooks (Husky equivalent) | pre-commit | installed by `just setup` |
| DB migrations | Alembic | `just migration name=...`, `just migrate` |
| Local services | Docker Compose | started by `just dev` |

Development is test-first. See [docs/testing-guide.md](docs/testing-guide.md).

### Editor setup

[`.editorconfig`](.editorconfig) sets the charset, line endings, and indentation for every file type, so your editor writes files correctly as you type. Make sure your editor reads it:

| Editor | Setup |
|---|---|
| VS Code / Cursor | install the [EditorConfig](https://marketplace.visualstudio.com/items?itemName=EditorConfig.EditorConfig) extension |
| JetBrains (PyCharm, etc.) | built in |
| Neovim 0.9+ | built in |
| Vim 9.1+ | add `packadd! editorconfig` to your vimrc |
| Zed | built in |
| Sublime Text | install the `EditorConfig` package via Package Control |
| Others | see [editorconfig.org](https://editorconfig.org/#download) |

The pre-commit hooks still fix trailing whitespace and missing final newlines, whatever your editor does.

## Repository layout

```
src/ooyok_api/     application (api → services → repositories → db)
tests/             unit, integration, api, contract, smoke
infra/terraform/   GCP infrastructure (staging, prod)
docs/              project documentation
.claude/           Claude Code settings, hooks, skills
```

## Environments

| Env | Where |
|---|---|
| dev | local Docker Compose |
| staging | GCP project `ooyok-staging` (auto-deploy from `main`) |
| prod | GCP project `ooyok-prod` (manual promote; created at launch) |

## Documentation

| Doc | What's in it |
|---|---|
| [PRD](docs/PRD.md) | scope, milestones, endpoints, validation, error codes, NFRs |
| [Architecture & infrastructure](docs/architecture-infra-guide.md) | system design, auth flows, caching, events, security, scaling, Redis ops, cost, multi-region |
| [GCP set-up](docs/GCP-set-up-guide.md) | provisioning steps and **launch settings** |
| [Testing](docs/testing-guide.md) | TDD workflow, test layers, first tests |
| [Harness](docs/harness-guide.md) | status of Claude Code setup, hooks, tooling, CI |
| [ADRs](docs/adr/) | architecture decision records |
| [CLAUDE.md](CLAUDE.md) | rules for Claude Code in this repo |
