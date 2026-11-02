# 0002. Firebase Authentication for identity

- Status: Accepted
- Date: 2026-10-30

## Context
Every routine belongs to a user, so auth blocks M1. Options considered: Firebase Authentication (hosted identity provider), Authlib (library to build OAuth/OIDC clients and servers), PyJWT (JWT encode/decode only). Goals: fast development, while understanding the password and OAuth login flows.

## Decision
Use **Firebase Authentication** for sign-up, password login, Google sign-in, email verification, password reset, and token refresh. The API verifies Firebase ID tokens with `firebase_admin.auth.verify_id_token()` and maps `sub` to an internal user. Both flows are documented in the architecture guide (§6).

## Consequences
- No password storage, reset emails, or brute-force protection to build or secure.
- Every login method converges on one token type, so the API stays simple.
- Vendor coupling to Firebase; internal `users.id` keeps the rest of the schema independent of `firebase_uid`.
- Upgrade path to Identity Platform (SLA, multi-tenancy) in place.

## Revisit when
Rehab features store health data: confirm compliance coverage (BAA) for the chosen product, or the product needs enterprise SSO or multi-tenancy (→ Identity Platform).
