# 0003. Self-managed Redis on Compute Engine instead of Memorystore

- Status: Accepted
- Date: 2026-10-30

## Context
Redis is used for caching and per-user rate limiting. Memorystore's smallest instance is ~US$35/month per environment, too much for a ~US$100/month total budget.

## Decision
Run Redis in a container on a small **Container-Optimized OS VM** (`e2-micro` staging, `e2-small` prod), private IP only, reached from Cloud Run via Direct VPC egress. Cache only: no persistence, `allkeys-lru`. The app treats Redis as optional and fails open to Postgres.

## Consequences
- Roughly US$7–13/month instead of ~US$35+.
- We own patching (COS auto-updates the OS; Redis version bumps via Terraform recreate the VM), monitoring (Ops Agent), and scaling (vertical only).
- Single node, no failover; acceptable because losing the cache only costs latency.
- Idempotency keys live in Postgres, not Redis, so correctness never depends on Redis.

## Revisit when
High availability is needed, the service goes multi-region, or budget allows. Migration is a `REDIS_URL` change.
