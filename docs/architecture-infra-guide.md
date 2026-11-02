# Architecture & Infrastructure Guide

How the ooyok API is built, deployed, and operated on GCP. For step-by-step provisioning, see [GCP-set-up-guide.md](GCP-set-up-guide.md). For the reasoning behind major choices, see [adr/](adr/).

## Contents
1. [Principles](#1-principles)
2. [System overview](#2-system-overview)
3. [GCP service map](#3-gcp-service-map)
4. [Application architecture](#4-application-architecture)
5. [Data model](#5-data-model)
6. [Authentication (Firebase)](#6-authentication-firebase)
7. [API security](#7-api-security)
8. [Caching strategy](#8-caching-strategy)
9. [Async processing: events and queues](#9-async-processing-events-and-queues)
10. [Scaling and latency](#10-scaling-and-latency)
11. [Redis operations (self-managed)](#11-redis-operations-self-managed)
12. [Environments](#12-environments)
13. [CI/CD](#13-cicd)
14. [Observability](#14-observability)
15. [Reliability: backups, DR, incidents](#15-reliability-backups-dr-incidents)
16. [Cost plan](#16-cost-plan)
17. [Multi-region roadmap](#17-multi-region-roadmap)
18. [Kubernetes decision](#18-kubernetes-decision)

---

## 1. Principles

- **Managed over self-run**, except where budget forces otherwise (Redis, see §11).
- **Stateless API.** All state lives in Postgres (source of truth), Redis (disposable cache), or Pub/Sub (in-flight events).
- **Degrade, don't fail.** If Redis is down, serve from Postgres. If Pub/Sub is down, events wait in the outbox.
- **Everything in Terraform**, with region and sizing as variables. Nothing hard-coded to `asia-east1`.
- **Build once, promote.** The image that passed staging is the image that runs in prod.

## 2. System overview

```
                 Client (Next.js, Firebase JS SDK)
                    │  HTTPS + Authorization: Bearer <Firebase ID token>
                    │  api.<domain> = DNS-only record (Cloudflare does not proxy the API)
                    ▼
     ┌───────────────────────────────────────────────────────────────────────┐
     │  Pre-launch: *.run.app or domain mapping (no edge protection)         │
     │  At launch:  Global external Application Load Balancer                │
     │              + Cloud Armor (WAF, per-IP rate limiting, L7 DDoS)       │
     └───────────────────────────────┬───────────────────────────────────────┘
                                     ▼
                     Cloud Run service: api (FastAPI)
                       │            │             │
          Direct VPC   │            │ Cloud SQL   │ publish after commit
          egress       ▼            ▼ connector   ▼
                 Redis VM       Cloud SQL      Pub/Sub topic: domain-events
                 (cache,        (Postgres)            │ push (OIDC-authenticated)
                 rate limit)       ▲                  ▼
                                   │           Cloud Run service: worker
                                   │           (stats, streaks, notifications)
                                   │
                    outbox table ◄─┘  swept every minute by Cloud Scheduler
                                      → Cloud Run job: outbox-relay
```

## 3. GCP service map

| Concern | GCP service | AWS equivalent | Notes |
|---|---|---|---|
| API compute | Cloud Run (service) | ECS Fargate | `api` and `worker` services |
| One-off / scheduled jobs | Cloud Run jobs + Cloud Scheduler | Lambda / ECS tasks + EventBridge | migrations, outbox sweeper |
| Relational DB | Cloud SQL for PostgreSQL | RDS | Enterprise edition, shared-core pre-launch |
| Cache | Redis on Compute Engine | ElastiCache | Memorystore later (§11) |
| Events | Pub/Sub | SNS + SQS | fan-out domain events |
| Task queue | Cloud Tasks | SQS | single-consumer jobs with retries (when needed) |
| Object storage | Cloud Storage | S3 | exercise media, exports (later) |
| Load balancer | Global external Application LB | ALB | **launch only** (§16); absorbs L3/L4 DDoS by default |
| WAF / rate limiting | Cloud Armor (policy on the LB) | AWS WAF + Shield | **launch only**; Cloudflare fronts the web app, not the API |
| CDN | Cloud CDN (optional) | CloudFront | only if the exercise library needs edge caching |
| API gateway | none | API Gateway | not needed; see below and [ADR 0006](adr/0006-no-api-gateway-edge-via-cloud-armor.md) |
| DNS | Cloudflare (DNS-only record for the API) | Route 53 | the domain is registered and hosted on Cloudflare |
| Secrets | Secret Manager | Secrets Manager | |
| Identity | Firebase Authentication | Cognito | §6 |
| Container registry | Artifact Registry | ECR | |
| IaC | Terraform | CloudFormation / Terraform | state in GCS |
| Logs / metrics / traces | Cloud Logging / Monitoring / Trace (via OpenTelemetry) | CloudWatch / X-Ray | §14 |
| Errors | Sentry (optional) or Error Reporting | — | |

### Why there is no API gateway
Every gateway job is already covered: TLS and routing by the load balancer; WAF, per-IP rate limiting, and DDoS by Cloud Armor; token verification, per-user rate limiting, validation, and CORS by FastAPI. The API must verify the user anyway for object-level authorization (§7), so gateway auth would only duplicate it while adding a hop, cost, and a second OpenAPI config. Add one when there are multiple backend services, a public third-party API with keys and quotas, or protocol translation needs ([ADR 0006](adr/0006-no-api-gateway-edge-via-cloud-armor.md)).

## 4. Application architecture

### Stack
Python 3.14 · FastAPI · Pydantic v2 · SQLAlchemy 2.0 (async) + asyncpg · Alembic · redis-py (asyncio) · google-cloud-pubsub · firebase-admin · OpenTelemetry · uv.

### Layout

```
src/ooyok_api/
  main.py                  # app factory, middleware, router registration
  api/
    v1/routines.py         # HTTP layer: parse, authorize, call service, shape response
    v1/exercises.py
    deps.py                # FastAPI dependencies: current_user, db session, cache
    errors.py              # exception → problem+json mapping
  schemas/                 # Pydantic request/response models (camelCase aliases)
  services/                # use cases; business rules; transaction boundaries
  repositories/            # SQLAlchemy queries only; no business logic
  db/
    models.py              # ORM models (snake_case)
    session.py
  migrations/              # Alembic
  core/
    config.py              # pydantic-settings; all config from env
    auth.py                # Firebase token verification
    cache.py               # Redis client wrapper with fail-open behaviour
    events.py              # outbox writer + publisher
    logging.py, telemetry.py
  workers/                 # Pub/Sub push handlers (deployed as the worker service)
tests/                     # see testing-guide.md
infra/terraform/           # see §12
```

### Layering rules
- `api` → `services` → `repositories` → `db`. Never skip downward, never import upward.
- Routers contain no SQL and no business rules.
- Services own transactions (`async with session.begin()`), and write outbox events in the same transaction.
- Pydantic schemas ≠ ORM models. Map explicitly in the service or repository.

### API conventions
- Versioned under `/v1`.
- **JSON is camelCase** (Pydantic `alias_generator=to_camel`, `populate_by_name=True`); Python and DB are snake_case. The front end consumes the API shape directly.
- IDs are **UUIDv7** (time-ordered, index-friendly, safe across shards). Generated server-side; clients may send one later for offline sync.
- Timestamps are ISO 8601 UTC.
- Weight is stored and transferred in **kg**; kg/lb is a display preference.
- Enum values are stable snake_case keys (`barbell`, `upper_back`); the front end translates them with next-intl.
- Errors use **RFC 9457 `application/problem+json`** with a machine-readable `code`; the front end translates the code, never displays `detail` verbatim.
- Cursor pagination (`?cursor=…&limit=…`) for lists.
- `POST` endpoints accept an `Idempotency-Key` header (§7).
- OpenAPI is the contract; the front end generates TypeScript types from it (`openapi-typescript`).

## 5. Data model

Initial tables for the routine milestone:

| Table | Key columns | Notes |
|---|---|---|
| `users` | `id` (uuid7), `firebase_uid` (unique), `home_region`, `timezone`, `weight_unit`, `created_at` | created on first authenticated request |
| `exercises` | `id`, `type`, `equipment`, `primary_muscle`, `secondary_muscles` (text[]) | seeded library; names live in front-end translations |
| `routines` | `id`, `user_id`, `title`, `notes`, `version`, `created_at`, `updated_at` | index `(user_id, updated_at desc)` |
| `routine_exercises` | `id`, `routine_id`, `position`, `exercise_id`, `notes`, `rest_seconds` | unique `(routine_id, position)` |
| `routine_sets` | `id`, `routine_exercise_id`, `position`, `type`, `weight_kg` (numeric), `reps`, `rep_range_start`, `rep_range_end`, `duration_seconds`, `distance_meters` | check `rep_range_start <= rep_range_end` |
| `idempotency_keys` | `(user_id, key)` PK, `request_hash`, `response_status`, `response_body`, `created_at` | expired by a daily job (24h) |
| `outbox` | `id`, `event_type`, `aggregate_id`, `payload` (jsonb), `created_at`, `published_at` | partial index on `published_at IS NULL` |

Design choices:
- A routine is an **aggregate**: create and update write the routine and its children in one transaction. Updates replace children wholesale and bump `version` (optimistic locking via `If-Match` / `version` in the body).
- Every user-owned row is reachable from `user_id`, which keeps authorization simple and makes per-user export, deletion, and future regional sharding possible.
- `home_region` and `timezone` exist from day one (streaks and calendars depend on the user's local date; multi-region depends on home region).

## 6. Authentication (Firebase)

**Decision:** Firebase Authentication handles identity end to end (sign-up, password login, Google sign-in, email verification, password reset, token refresh). The API only verifies ID tokens with `firebase_admin.auth.verify_id_token()`. See [ADR 0002](adr/0002-firebase-authentication.md).

### Password login flow

```
Browser (Firebase SDK)              Firebase Auth                 ooyok API
  │ signInWithEmailAndPassword ───────►│                              │
  │                                    │ checks password hash,        │
  │                                    │ brute-force protection       │
  │◄──── ID token (JWT, 1h) + refresh token                           │
  │                                                                   │
  │ GET /v1/routines  Authorization: Bearer <ID token> ──────────────►│
  │                                                                   │ verify_id_token():
  │                                                                   │  • signature (RS256, Google public keys)
  │                                                                   │  • iss = https://securetoken.google.com/<project>
  │                                                                   │  • aud = <project>, exp/iat valid
  │                                                                   │ sub → users.firebase_uid → user_id
  │◄────────────────────────────────────────────────────── 200 ───────│
  │                                                                   │
  │ (≈1h later) SDK silently exchanges refresh token for a new ID token
```

### Google sign-in (OAuth 2.0 / OpenID Connect) flow

```
Browser ──signInWithPopup(GoogleAuthProvider)──► Google consent screen
Google ──authorization code──► Firebase Auth (exchanges code with Google, gets Google ID token)
Firebase Auth ──Firebase ID token + refresh token──► Browser
Browser ──Bearer <Firebase ID token>──► ooyok API   (identical to password flow from here)
```

The API never sees passwords or Google tokens; every login method converges on the same Firebase ID token.

### API-side rules
- `core/auth.py` exposes a `current_user` dependency: verify the token, upsert the `users` row on first sight, return the internal user.
- `check_revoked=True` only on sensitive operations (account deletion, export); it costs a network call.
- Tests override `current_user` via `app.dependency_overrides`; e2e uses the Firebase Auth emulator (`FIREBASE_AUTH_EMULATOR_HOST`).
- Firebase upgrades in place to **Identity Platform** (SLA, multi-tenancy, blocking functions). Before storing rehab/health data, confirm which product is covered by Google's healthcare compliance terms (BAA).

## 7. API security

Baseline aligned with the OWASP API Security Top 10:

| Risk | Control |
|---|---|
| Broken object-level authorization (IDOR) | Every repository query filters by `user_id`. Another user's resource returns **404**, not 403. Tested explicitly. |
| Broken authentication | Firebase ID token required on every non-health endpoint; no API-issued sessions. |
| Unrestricted resource consumption | Pydantic limits (see [PRD.md](PRD.md#validation-limits)); request body cap (e.g. 256 KB); cursor pagination with max `limit`; rate limiting. |
| Rate limiting | Cloud Armor rate-based rules per IP (at launch); Redis fixed-window per user in the API (fail-open if Redis is down). |
| Edge attacks (DDoS, common exploits) | Global LB absorbs L3/L4 DDoS by default; Cloud Armor preconfigured WAF rules (OWASP: SQLi, XSS, LFI, RCE), run in preview mode first, then enforced. Pre-launch there is no edge layer, so auth + app rate limiting are the only protection. |
| Duplicate writes | `Idempotency-Key` on POST. Stored in Postgres (`idempotency_keys`) so it works without Redis; same key + same body replays the stored response, same key + different body → `409 idempotency_conflict`. |
| Mass assignment | Separate create/update/response schemas; `extra="forbid"` on request models. |
| Security misconfiguration | CORS allowlist from config; no stack traces in responses; security headers; `/docs` disabled in prod. |
| Network exposure | At launch, Cloud Run ingress = `internal-and-cloud-load-balancing`, so `*.run.app` can't bypass the LB and Cloud Armor; Redis has no public IP; Cloud SQL accepts only IAM-authenticated connector traffic. |
| Secrets | Secret Manager mounted as env vars; one service account per service with least privilege; GitHub Actions uses Workload Identity Federation (no JSON keys). |
| Supply chain | `uv.lock` pinned; Dependabot; `pip-audit` in CI; gitleaks in pre-commit and CI. |

## 8. Caching strategy

| Data | Strategy | Invalidation |
|---|---|---|
| Exercise library | `Cache-Control: public, max-age=86400` + `ETag` (browsers cache it); in-process LRU in each instance; Cloud CDN on the LB backend only if needed | new library version → new ETag (seed version number) |
| Routine list (`RoutineSummary[]`) per user | Cache-aside in Redis: key `routines:list:{user_id}:v{n}` with a 5-minute TTL | writes `INCR routines:ver:{user_id}`, so old keys are simply never read again |
| Single routine | Not cached initially. Primary-key lookups are fast; add caching only if metrics show need | — |
| Auth public keys | Cached in-process by firebase-admin | handled by library |

Fail-open rule: every Redis call goes through `core/cache.py`, which catches connection errors, logs and counts them, and falls through to Postgres. The TTL bounds staleness if a version bump was missed during a Redis blip.

## 9. Async processing: events and queues

Creating a routine is a single short transaction and does **not** need a queue. Queues exist for work that should not block the request:

- **Domain events (Pub/Sub):** `routine.created`, `routine.updated`, later `workout.completed`. The worker consumes them to update streaks, statistics, and goal progress (PRD features: Goal, Statistics).
- **Tasks (Cloud Tasks), when needed:** single-consumer jobs with retry and rate control, e.g. sending emails, generating exports.

### Transactional outbox
1. The service writes the business rows **and** an `outbox` row in the same DB transaction.
2. After commit, the API tries to publish immediately (low latency) and marks `published_at`.
3. A Cloud Scheduler job triggers the `outbox-relay` Cloud Run job every minute to publish anything left unpublished (Pub/Sub outage, instance crash).

This avoids the dual-write bug (DB commit succeeded, publish failed, or the reverse).

### Consumers
- Pub/Sub push subscription → `worker` Cloud Run service, authenticated with an OIDC token from a dedicated service account.
- Delivery is at-least-once, so handlers are **idempotent** (dedupe on event id in a `processed_events` table).
- Dead-letter topic after 5 attempts; alert on DLQ depth.

## 10. Scaling and latency

### Targets (post-launch)
| Metric | Target |
|---|---|
| Read p95 | < 150 ms |
| Write p95 | < 300 ms |
| Availability | 99.9% monthly |

### Cold starts
Cloud Run only cold-starts when no warm instance can take a request.
- `min-instances = 1` in prod (0 in staging, and 0 in prod before launch).
- `--cpu-boost` (startup CPU boost).
- Small image (slim base, multi-stage build), no heavy imports at module load, lazy DB/Redis connections.

### Throughput
- Async FastAPI, one uvicorn worker per container; Cloud Run `concurrency` ≈ 40–80 per instance (tune with load tests).
- `max-instances` capped so that `max_instances × db_pool_size + jobs < Cloud SQL max_connections`. Pool exhaustion is the first thing that breaks under load.
- Avoid N+1 queries with `selectinload`; indexes as in §5.
- Load test with k6 before launch and after major changes (see [testing-guide.md](testing-guide.md#load-tests)).

## 11. Redis operations (self-managed)

Memorystore's smallest instance costs about US$35/month per environment, which doesn't fit the budget. Redis runs on a small Compute Engine VM instead. See [ADR 0003](adr/0003-self-managed-redis-on-compute-engine.md).

### Setup
- **VM:** `e2-micro` (staging) / `e2-small` (prod) in `asia-east1`, **Container-Optimized OS**, no external IP.
- **Redis:** the official `redis:<major.minor>-alpine` image, pinned to a minor version, started by a systemd unit declared in cloud-init (Terraform `metadata.user-data`).
- **Config:** `maxmemory` ≈ 70% of RAM, `maxmemory-policy allkeys-lru`, persistence **off** (`save ""`, `appendonly no`). It is a cache; losing it is fine.
- **Network:** Cloud Run reaches it through **Direct VPC egress** (`--network`, `--subnet`, `--vpc-egress=private-ranges-only`; no connector cost). The firewall allows TCP 6379 only from the Cloud Run subnet.
- **Auth:** `requirepass` from Secret Manager; the API reads `REDIS_URL` from Secret Manager.

### Patching
- **OS:** Container-Optimized OS auto-updates (`cos-update-strategy=update_enabled`) and applies updates on reboot. Schedule reboots in a maintenance window, or let them happen; the app fails open.
- **Redis version:** bump the pinned image tag in Terraform → `terraform apply` recreates the VM. Expect about 1 minute of cache misses.
- Subscribe to Redis security advisories; check for updates monthly.

### Scaling
- **Vertical only:** change `machine_type` in Terraform (`e2-small` → `e2-medium` → …). It's a single node with no replicas and no failover.
- Watch `used_memory`, `evicted_keys`, `connected_clients`, and CPU (Ops Agent → Cloud Monitoring). Alert when memory > 85% or the eviction rate rises steadily.

### When to move to Memorystore
Move when **any** of these is true: you need high availability or failover, you go multi-region (§17), or the budget allows (~US$35+/month per environment). Migration is a config change, because the app only knows `REDIS_URL`.

## 12. Environments

| Env | Where | Purpose | Exists |
|---|---|---|---|
| **dev** | Local: Docker Compose (Postgres, Redis, Pub/Sub emulator, Firebase Auth emulator) | daily development, unit/integration/API tests, local e2e | always |
| **staging** | GCP project `ooyok-staging` | deployed integration, e2e smoke, migration rehearsal | from first deploy |
| **prod** | GCP project `ooyok-prod` | real users | **created at launch** |

### Terraform layout
```
infra/terraform/
  modules/
    network/            # VPC, subnet, firewall
    cloud_run_service/  # api, worker
    cloud_sql/
    redis_vm/
    pubsub/
    load_balancer/      # created only when enable_lb = true
    monitoring/         # dashboards, alerts, uptime checks
  envs/
    staging/            # main.tf, terraform.tfvars, backend → gs://<staging-state-bucket>
    prod/
```

Launch-time switches live in `envs/prod/terraform.tfvars`. The full list is in [GCP-set-up-guide.md → Launch settings](GCP-set-up-guide.md#launch-settings-pre-launch--public-release).

## 13. CI/CD

GitHub Actions; auth to GCP via Workload Identity Federation.

| Workflow | Trigger | Steps |
|---|---|---|
| `ci.yml` | every PR and push | `uv sync` → ruff → mypy → pytest (unit, integration, API via testcontainers) → Schemathesis → pip-audit → gitleaks → OpenAPI diff check |
| `deploy.yml` | push to `main` | build image (tag = git SHA) → push to Artifact Registry → staging: run migration job → deploy with no traffic → smoke tests → shift 100% |
| `promote.yml` | manual (prod) | same image SHA → prod migration job → deploy with no traffic → smoke → traffic 10% → 50% → 100% |

Migration rules: only expand/contract (backward-compatible) migrations, because old and new revisions run at the same time during traffic shifts. Never edit a merged migration.

## 14. Observability

- **Logs:** structured JSON to stdout, so Cloud Logging parses severity and trace fields. Every log line carries `trace_id` and `user_id` (hashed). Never log tokens, request bodies with health data, or PII.
- **Traces:** OpenTelemetry SDK with FastAPI, SQLAlchemy, redis, and httpx instrumentation → Cloud Trace. Using OTel keeps a move to Datadog or Grafana possible.
- **Metrics:** request rate, latency (p50/p95/p99), and error rate per route; DB pool usage; cache hit ratio; Redis fail-open count; outbox lag (oldest unpublished row age); DLQ depth.
- **Alerts (Cloud Monitoring):** 5xx rate > 1% for 5 min; p95 over target for 10 min; outbox lag > 5 min; DLQ > 0; uptime check failing; budget thresholds.
- **Errors:** Sentry (free tier) or Error Reporting.

## 15. Reliability: backups, DR, incidents

- **Cloud SQL:** automated daily backups plus point-in-time recovery (prod). Targets: RPO ≤ 5 min, RTO ≤ 1 h. **Rehearse a restore into staging once before launch.**
- **High availability:** Cloud SQL regional HA (`availability_type = REGIONAL`) roughly doubles DB cost; enable it when revenue or users justify it.
- **Graceful degradation:** Redis down → Postgres; Pub/Sub down → outbox accumulates; worker down → events retry, then go to the DLQ.
- **Runbooks** (`docs/runbooks/`, to be written): DB unreachable, 5xx spike, bad deploy rollback (`gcloud run services update-traffic --to-revisions=<prev>=100`), DLQ growing, Redis down.

## 16. Cost plan

Budget: **≈ US$100/month (NT$3,000)**. Estimates for `asia-east1`; verify with the GCP pricing calculator.

### Pre-launch (staging only)
| Item | Est. / month |
|---|---|
| Cloud Run api + worker (min 0) | $0–2 |
| Cloud SQL `db-f1-micro`, stopped when idle | $3–10 |
| Redis VM `e2-micro` (or off) | $0–7 |
| Pub/Sub, Cloud Tasks, Secret Manager, Artifact Registry, logging, Firebase Auth | ~$0–3 (free tiers) |
| **Total** | **~$5–20** |

### After launch (staging + prod)
| Item | Prod | Staging |
|---|---|---|
| Cloud Run (prod min 1) | $10–20 | $0–2 |
| Cloud SQL | $10–28 | $3–10 |
| Redis VM | $7–13 | $0–7 |
| Global external LB | ~$18 | — |
| Cloud Armor (1 policy + a few rules + per-request fee) | ~$7–10 | — |
| Misc (free tiers mostly) | $0–5 | $0–3 |
| **Total** | **~$50–95** | **~$5–20** |

At the upper estimates, staging + prod can reach the US$100 budget; stop the staging DB when idle and keep staging Redis off unless testing caching.

Cost levers: don't create prod until launch; no load balancer or Cloud Armor until launch; staging min instances 0; stop the staging DB when idle (`--activation-policy=NEVER`); budget alerts at 50/90/100%.

## 17. Multi-region roadmap

| Layer | Global plan |
|---|---|
| Global LB + Cloud Armor, Pub/Sub, Firebase Auth | already global |
| Cloud Run | deploy the same image to more regions; the global LB routes each user to the nearest healthy region (serverless NEG per region) |
| Redis | one cache per region (caches needn't be shared) |
| Cloud Storage | multi-region buckets |
| **Postgres, step 1** | primary in `asia-east1` + **cross-region read replicas**. Reads are local; writes go to the primary (+100–200 ms for distant users, acceptable for logging workouts) |
| **Postgres, step 2** | if data-residency rules apply (likely for rehab/health data): **regional databases, users pinned by `home_region`**; a lightweight global directory maps `firebase_uid → home_region` |
| Beyond | Spanner/AlloyDB only when scale and budget justify it |

Prepared today at near-zero cost:
- region is a Terraform variable;
- `DATABASE_URL` (writes) and `DATABASE_READ_URL` (reads) are separate settings, initially the same value;
- UUIDv7 IDs (no cross-database collisions);
- `users.home_region` column;
- UTC timestamps plus the user's IANA timezone.

## 18. Kubernetes decision

**Not now.** Cloud Run runs the same Docker image GKE would, scales in seconds, and needs no cluster operations, so moving later is configuration work, not a rewrite. See [ADR 0001](adr/0001-cloud-run-over-gke-and-compute-engine.md).

Optional learning milestone (post-launch): move the `worker` service to **GKE Autopilot** via Terraform (Deployment, HPA, Workload Identity), keeping `api` on Cloud Run.
