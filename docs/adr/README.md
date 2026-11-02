# Architecture Decision Records

One short file per significant decision: what we decided, why, and what it costs us. Records are immutable once accepted; to change a decision, add a new ADR that supersedes the old one.

| # | Decision | Status |
|---|---|---|
| [0001](0001-cloud-run-over-gke-and-compute-engine.md) | Cloud Run over GKE and Compute Engine | Accepted |
| [0002](0002-firebase-authentication.md) | Firebase Authentication for identity | Accepted |
| [0003](0003-self-managed-redis-on-compute-engine.md) | Self-managed Redis on Compute Engine instead of Memorystore | Accepted |
| [0004](0004-transactional-outbox-for-domain-events.md) | Transactional outbox for domain events | Accepted |
| [0005](0005-single-region-with-multi-region-path.md) | Single region (`asia-east1`) with a multi-region path | Accepted |
| [0006](0006-no-api-gateway-edge-via-cloud-armor.md) | No API gateway; edge protection via Cloud Armor | Accepted |

## Template

```markdown
# NNNN. Title

- Status: Proposed | Accepted | Superseded by NNNN
- Date: YYYY-MM-DD

## Context
## Decision
## Consequences
## Revisit when
```
