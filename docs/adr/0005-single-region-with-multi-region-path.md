# 0005. Single region (asia-east1) with a multi-region path

- Status: Accepted
- Date: 2026-10-30

## Context
Initial users are expected near Taiwan; the long-term target is global. Multi-region from day one would multiply cost and complexity.

## Decision
Deploy everything in **`asia-east1`**. Keep multi-region cheap to add later: region as a Terraform variable, separate `DATABASE_URL` / `DATABASE_READ_URL` settings, UUIDv7 IDs, `users.home_region`, UTC timestamps plus user timezone.

## Consequences
- Lowest cost and simplest operations now.
- Distant users see higher latency until expansion.
- Expansion path: more Cloud Run regions behind the global LB → cross-region read replicas → regional databases keyed by `home_region` if data-residency rules require.

## Revisit when
A meaningful share of users is outside East Asia, latency targets are missed for them, or data-residency law applies.
