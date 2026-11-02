# CLAUDE.md

FastAPI backend for ooyok, a simplified Hevy-style workout logger that will pivot to rehabilitation. Deployed on GCP Cloud Run (`asia-east1`).

**Status:** docs only. The scaffold (`pyproject.toml`, `justfile`, `src/`, `tests/`, hooks, CI) does not exist yet. Commands below become valid once milestone M0 is built. See `docs/harness-guide.md` for what exists.

## Read first
- `docs/PRD.md`: scope, endpoints, validation limits, error codes
- `docs/architecture-infra-guide.md`: layers, data model, caching, events, security
- `docs/testing-guide.md`: TDD workflow and test layers
- `docs/harness-guide.md`: tooling status
- `docs/adr/`: why things are the way they are

## Commands
```bash
just setup        # uv sync + pre-commit install
just dev          # docker compose up + uvicorn --reload
just test-unit    # fast unit tests
just test         # unit + integration + api + contract
just lint         # ruff + mypy
just fix          # ruff fix + format
just migration name=add_x   # alembic autogenerate
just migrate      # alembic upgrade head
```
Run Python through `uv run`, never a bare `python`/`pip`.

## Workflow: TDD, always
1. Write a failing test first and run it to see it fail.
2. Write the minimum code to pass.
3. Refactor with tests green.
Bug fixes start with a reproducing test. Use real Postgres via testcontainers; don't mock the DB session.

## Architecture rules
- Layers: `api/` → `services/` → `repositories/` → `db/`. No upward imports, no skipping layers.
- Routers: HTTP only. No SQL, no business rules.
- Services own transactions and write outbox events in the same transaction.
- Every user-owned query filters by `user_id`. Another user's resource → 404.
- Redis access only through `core/cache.py`, which must fail open.
- Pydantic schemas and ORM models are separate types.

## Conventions
- JSON is **camelCase** (Pydantic alias generator); Python and DB are snake_case.
- IDs are UUIDv7. Timestamps are UTC ISO 8601.
- Weight is always kg (`weight_kg`).
- Enum values are snake_case keys, never display text.
- Errors are RFC 9457 problem+json with a stable `code` (list in `docs/PRD.md`).
- Config comes only from env via `core/config.py` (pydantic-settings).
- Region, sizes, and URLs are never hard-coded.
- Read paths use the read DB URL setting; writes use the primary.

## Never
- Edit a migration that is already on `main`. Add a new one.
- Run `terraform apply`/`destroy` or `gcloud … delete`. Propose the command instead.
- Read or write `.env*` or `*.tfstate`.
- Log tokens, request bodies containing health data, or PII.
- Add a dependency without saying why.

## Keep docs in sync
- Changing `CLAUDE.md`, `.claude/`, `.pre-commit-config.yaml`, `justfile`, tool config in `pyproject.toml`, or `.github/` → update `docs/harness-guide.md` status table.
- Adding/changing an endpoint → update `docs/PRD.md` endpoint table and the OpenAPI snapshot.
- A significant architectural choice → add an ADR in `docs/adr/`.
