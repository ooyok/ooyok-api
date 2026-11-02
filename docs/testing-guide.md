# Testing Guide

This repo is developed **test-first**. Every behaviour change starts with a failing test.

## The TDD loop

1. **Red:** write the smallest test that describes the next behaviour. Run it and watch it fail for the right reason.
2. **Green:** write the least code that makes it pass.
3. **Refactor:** clean up with the tests green. Run the full suite before committing.

Rules:
- No production code without a failing test that needs it.
- Bug fixes start with a test that reproduces the bug.
- Don't mock what you own at the boundary you're testing. Use a **real Postgres** (testcontainers), not a mocked session.
- Tests must be independent and runnable in any order.

## Tooling

| Tool | Use |
|---|---|
| `pytest` | runner |
| `pytest-asyncio` | async tests (`asyncio_mode = "auto"`) |
| `httpx.AsyncClient` + `ASGITransport` | call the FastAPI app in-process, no server |
| `testcontainers` | real Postgres and Redis in Docker for integration/API tests |
| `polyfactory` | build valid request payloads and models |
| `pytest-cov` | coverage; CI fails under the threshold |
| `hypothesis` | property tests for validation rules (optional) |
| `schemathesis` | generates requests from the OpenAPI schema to find crashes and contract violations |
| `k6` | load tests against staging |
| Playwright | stack-level e2e, lives with the front end |

## Test layers

| Layer | Folder | Marker | What it covers | Dependencies | Runs |
|---|---|---|---|---|---|
| Unit | `tests/unit/` | `unit` | schemas/validation, services with fake repositories, pure helpers | none | Claude's Stop hook, pre-push, CI |
| Integration | `tests/integration/` | `integration` | repositories against real Postgres; cache wrapper against real Redis; outbox writer | testcontainers | CI, `just test` |
| API | `tests/api/` | `api` | full HTTP path through FastAPI: auth, validation, status codes, response shape | testcontainers | CI, `just test` |
| Contract | `tests/contract/` | `contract` | OpenAPI snapshot diff; Schemathesis fuzzing | app in-process | CI |
| Smoke | `tests/smoke/` | `smoke` | a few real requests against a deployed URL | staging/prod | after each deploy |
| Load | `loadtests/` (k6) | — | latency targets and throughput | staging | before launch, after big changes |
| E2E | front-end repo | — | browser → front end → API → DB with the Firebase Auth emulator | Docker Compose | front-end CI; smoke subset on staging |

## Fixtures and isolation

- **Database:** one Postgres container per test session; run `alembic upgrade head` once. Each test runs inside a transaction rolled back at the end (SQLAlchemy `join_transaction_mode="create_savepoint"`), so services that commit still roll back.
- **Auth:** override the `current_user` dependency with a fixture user (`app.dependency_overrides`). One dedicated test module covers `core/auth.py` by stubbing `firebase_admin.auth.verify_id_token` for valid, expired, revoked, and malformed tokens.
- **Second user:** a `other_user` fixture exists to test object-level authorization.
- **Pub/Sub:** a `FakePublisher` records published events; one integration test uses the Pub/Sub emulator.
- **Time and IDs:** inject a clock and an ID generator so tests can assert exact values.
- **Exercise library:** a small seeded set loaded by a fixture.

## First tests for `POST /v1/routines` (M1)

Write these in order; each should fail before the code exists.

1. Valid payload → `201`, `Location` header, camelCase body with `id`, `version = 1`, timestamps.
2. `GET /v1/routines/{id}` returns what was created (round trip).
3. No/invalid token → `401 unauthenticated` (problem+json).
4. Validation → `422 validation_error` with the failing `field`:
   - empty or 101-char title
   - 0 or 51 exercises; 0 or 31 sets
   - negative `weightKg`; `repRange.start > end`
   - unknown extra field
5. Non-existent `exerciseId` → `422 unknown_exercise`.
6. User B fetching user A's routine → `404 routine_not_found`.
7. Same `Idempotency-Key` + same body twice → same `id`, one row in DB.
8. Same `Idempotency-Key` + different body → `409 idempotency_conflict`.
9. Creating a routine writes one `routine.created` outbox row in the same transaction (rolled back together on failure).
10. Body over 256 KB → `413 payload_too_large`.

M2 adds: list cache invalidated after create/update (version-key bump); Redis down → list still served from Postgres; `version_conflict` on stale update; `429` with `Retry-After`.

## Coverage

- CI threshold: **85% line coverage overall**, **95% for `services/` and `core/auth.py`**.
- Coverage is a floor, not the goal; untested branches in services are review blockers.

## Commands

```bash
just test            # all local layers (unit + integration + api + contract)
just test-unit       # fast; what the Stop hook runs
just test-cov        # with coverage report
just smoke URL=...   # smoke tests against a deployed environment
```

(`just` recipes are defined in the `justfile`; see [harness-guide.md](harness-guide.md).)

## Load tests

`loadtests/routines.js` (k6) thresholds mirror the PRD targets:

```js
export const options = {
  thresholds: {
    'http_req_duration{kind:read}': ['p(95)<150'],
    'http_req_duration{kind:write}': ['p(95)<300'],
    http_req_failed: ['rate<0.01'],
  },
};
```

Run against staging with prod-like settings (`min-instances=1`) so results are meaningful.

## CI gates

A PR cannot merge unless: ruff, ruff format check, mypy, all test layers, coverage thresholds, Schemathesis, pip-audit, gitleaks, and the OpenAPI diff check pass. Intentional API changes update the OpenAPI snapshot in the same PR.
