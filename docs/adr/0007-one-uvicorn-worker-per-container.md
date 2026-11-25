# 0007. One uvicorn worker per container; scale with Cloud Run instances

- Status: Accepted
- Date: 2026-11-10

## Context
A Python process with the GIL uses about one CPU core, so there are two ways to run more copies of the API: more uvicorn **workers** (processes inside one container, sharing its CPU and memory, fixed at startup) or more **containers** (Cloud Run instances, each with its own CPU and memory, added and removed by traffic). The API is async and I/O-bound: most request time is spent waiting on Postgres or Redis. Staging instances will likely have 1 vCPU.

## Decision
Run **one uvicorn worker per container** and let Cloud Run scale the number of instances. One async worker serves many concurrent requests (Cloud Run `concurrency` ≈ 40–80).

## Consequences
- No CPU contention or duplicated app memory from extra processes on a 1 vCPU instance.
- Faster cold starts: one process to start per instance.
- Idle capacity scales down (to zero in staging) instead of N processes running all the time.
- The DB connection limit stays `max_instances × db_pool_size + jobs < Cloud SQL max_connections`; each extra worker would multiply the pool.
- uvicorn is PID 1 and receives SIGTERM directly, so it drains in-flight requests on scale-down without a process manager.
- CPU-heavy request work would block the event loop of that instance; move such work to a background job or the worker service.

## Revisit when
Instances get 2+ vCPUs for CPU-bound work (then workers ≈ vCPUs), the API moves to fixed servers that can't scale out, or the free-threaded (no-GIL) Python build becomes the default and the dependencies support it.
