# ooyok API: Product Requirements

Scope and requirements for the API layer. The product-level PRD (features, front-end tech, references) lives in `ooyok-doc/docs/product-requirements.md`; the front-end data shapes live in `ooyok-doc/brainstrom/workout-log/data/front-schema.md`.

## Vision

A simplified workout-logging service inspired by Hevy, built to pivot toward **rehabilitation** later. Version 1 covers routines; goals, statistics, and workout logging follow.

Because of the rehab pivot, user data is treated as potentially **health data** from day one (see [Privacy and compliance](#privacy-and-compliance)).

## Milestones

| Milestone | Scope | Status |
|---|---|---|
| **M0: Foundation** | Repo scaffold, tooling, Claude Code setup, CI, local Docker Compose, staging on GCP, `/health` | planned |
| **M1: Create routine** | Firebase auth, `users`, exercise library seed, `POST /v1/routines`, `GET /v1/routines/{id}`, `GET /v1/exercises` | planned |
| **M2: Manage routines** | `GET /v1/routines` (RoutineSummary list), `PUT /v1/routines/{id}`, `DELETE /v1/routines/{id}`, Redis caching, rate limiting | planned |
| **M3: Workouts and goals** | log a workout from a routine, weekly goal (n days/week), domain events + worker | planned |
| **M4: Statistics** | calendar, streaks, notes | planned |
| **Launch** | prod project, load balancer, Cloud Armor, alerts ([launch settings](GCP-set-up-guide.md#launch-settings-pre-launch--public-release)) | planned |

## Out of scope (for now)
- Routine folders
- Supersets
- Custom (user-defined) exercises
- Summary panel
- Social features, sharing, public profiles
- Multi-region deployment (prepared for; see [architecture §17](architecture-infra-guide.md#17-multi-region-roadmap))

## M1 API

All endpoints except `/health` require `Authorization: Bearer <Firebase ID token>`.

| Method | Path | Purpose | Success |
|---|---|---|---|
| `GET` | `/health` | liveness: process is up (no auth, no dependency checks). Paths ending in `z` are avoided on Cloud Run | `200` |
| `GET` | `/v1/exercises` | exercise library for the picker; optional `equipment`, `muscle` filters | `200`, cacheable |
| `POST` | `/v1/routines` | create a routine | `201` + `Location` |
| `GET` | `/v1/routines/{id}` | fetch one routine | `200` |

### `POST /v1/routines`

Headers: `Authorization`, optional `Idempotency-Key` (UUID recommended).

Request:
```json
{
  "title": "Upper Body A",
  "notes": null,
  "exercises": [
    {
      "exerciseId": "0190f3a2-...",
      "notes": "Slow eccentric",
      "restSeconds": 90,
      "sets": [
        { "type": "warmup", "weightKg": 40, "reps": 10, "repRange": null, "durationSeconds": null, "distanceMeters": null },
        { "type": "normal", "weightKg": 60, "reps": null, "repRange": { "start": 8, "end": 12 }, "durationSeconds": null, "distanceMeters": null }
      ]
    }
  ]
}
```

Response `201`:
```json
{
  "id": "0190f3b7-...",
  "title": "Upper Body A",
  "notes": null,
  "exercises": [ "...same shape as request..." ],
  "version": 1,
  "createdAt": "2026-10-30T08:00:00Z",
  "updatedAt": "2026-10-30T08:00:00Z"
}
```

### Shared types
Enum values match the front-end schema exactly (snake_case keys):
- `SetType`: `normal | warmup | failure | dropset`
- `ExerciseType`: `weight_reps | reps_only | bodyweight_reps | bodyweight_assisted_reps | duration | weight_duration | distance_duration | short_distance_weight`
- `EquipmentType`, `MuscleGroup`: as in the front-end schema.

### Validation limits

Proposed defaults; adjust when real usage is known.

| Field | Rule |
|---|---|
| `title` | 1–100 chars, trimmed |
| `notes` (routine, exercise) | ≤ 1,000 chars or null |
| `exercises` | 1–50 items |
| `sets` per exercise | 1–30 items |
| `exerciseId` | must exist in the library, else `422 unknown_exercise` |
| `restSeconds` | 0–3,600 or null |
| `weightKg` | 0–1,000, max 2 decimals, or null |
| `reps` | 0–1,000 or null |
| `repRange` | `1 ≤ start ≤ end ≤ 1,000`, or null |
| `durationSeconds` | 0–86,400 or null |
| `distanceMeters` | 0–1,000,000 or null |
| unknown fields | rejected (`422`) |
| request body | ≤ 256 KB |

Fields irrelevant to an exercise's `type` are allowed to be null; they are not rejected in M1.

### Error codes

Errors use `application/problem+json` with a stable `code` the front end translates via next-intl.

| HTTP | `code` | When |
|---|---|---|
| 400 | `bad_request` | malformed JSON |
| 401 | `unauthenticated` | missing/invalid/expired token |
| 404 | `routine_not_found` | routine doesn't exist **or belongs to another user** |
| 409 | `idempotency_conflict` | same key reused with a different body |
| 409 | `version_conflict` | (M2) stale `version` on update |
| 413 | `payload_too_large` | body over limit |
| 422 | `validation_error` | field rules (includes `errors[]` with `field` + `code`) |
| 422 | `unknown_exercise` | `exerciseId` not in library |
| 429 | `rate_limited` | (M2) per-user rate limit; includes `Retry-After` |
| 500 | `internal_error` | anything else; no internals leaked |

## Non-functional requirements

| Area | Requirement |
|---|---|
| Latency (post-launch) | read p95 < 150 ms, write p95 < 300 ms, measured at the load balancer |
| Availability (post-launch) | 99.9% monthly |
| Security | OWASP API Top 10 baseline ([architecture §7](architecture-infra-guide.md#7-api-security)) |
| Scalability | stateless horizontal scaling on Cloud Run; DB connection budget enforced |
| Degradation | API stays up if Redis or Pub/Sub is down |
| Observability | structured logs, traces, RED metrics per route, alerts |
| Data durability | daily backups + PITR in prod; RPO ≤ 5 min, RTO ≤ 1 h |
| Cost | ≤ US$100/month total ([architecture §16](architecture-infra-guide.md#16-cost-plan)) |
| Testing | TDD; CI gates on lint, types, tests, coverage ([testing-guide.md](testing-guide.md)) |
| i18n | API returns keys and codes, never translated display text |

## Privacy and compliance

The rehab pivot means health data. Cheap to do now, expensive later:
- All user data scoped by `user_id`; supports per-user **export** and **deletion** (account deletion endpoint before launch).
- No health data or tokens in logs.
- Audit log for access to sensitive data (introduce with the rehab features).
- `users.home_region` for future data residency.
- Before storing rehab data: review applicable law (e.g. HIPAA, GDPR, local regulations) and whether features count as medical advice, and confirm which GCP/Firebase services are covered by Google's healthcare terms.

## Open questions
- Exercise library source and licensing (own dataset; do not copy Hevy's library or media).
- Account deletion: hard delete vs. grace period.
- Offline workout logging (client-generated IDs + idempotency are already planned).
