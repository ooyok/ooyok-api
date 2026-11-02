# 0001. Cloud Run over GKE and Compute Engine

- Status: Accepted
- Date: 2026-10-30

## Context
The API needs low latency, horizontal scaling, and minimal operations for a solo developer on a ~US$100/month budget. Options: Cloud Run, GKE (Autopilot), Compute Engine managed instance groups.

## Decision
Run the `api` and `worker` services on **Cloud Run**. Prod uses `min-instances = 1` and startup CPU boost to avoid cold starts.

## Consequences
- No OS patching, TLS, health-check wiring, or rolling-deploy scripts; revisions and traffic splitting are built in.
- Scales out in seconds (a MIG takes minutes).
- Same Docker image would run on GKE, so moving later is configuration, not a rewrite.
- One always-warm instance costs ~US$10–20/month.
- Less hands-on Kubernetes experience; addressed by an optional post-launch milestone moving the worker to GKE Autopilot.

## Revisit when
Workloads need long-running non-HTTP processes, GPUs, or fine-grained networking that Cloud Run can't provide, or sustained traffic makes always-on VMs cheaper.
