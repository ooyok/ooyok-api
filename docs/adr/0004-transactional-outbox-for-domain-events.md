# 0004. Transactional outbox for domain events

- Status: Accepted
- Date: 2026-10-30

## Context
Domain events (`routine.created`, later `workout.completed`) feed streaks, statistics, and goals via Pub/Sub. Writing to the DB and publishing to Pub/Sub separately risks one succeeding without the other.

## Decision
Services write an `outbox` row in the same transaction as the business change. The API publishes right after commit; a Cloud Scheduler-triggered `outbox-relay` job publishes anything left every minute. Consumers are idempotent (dedupe on event id).

## Consequences
- No lost or phantom events; Pub/Sub outages only delay processing.
- Extra table, relay job, and an "outbox lag" metric to monitor.
- At-least-once delivery means every consumer must be idempotent.

## Revisit when
Event volume makes polling inefficient (consider Postgres logical replication / CDC).
