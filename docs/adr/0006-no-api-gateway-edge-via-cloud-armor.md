# 0006. No API gateway; edge protection via Cloud Armor

- Status: Accepted
- Date: 2026-10-30

## Context
The domain is registered and hosted on Cloudflare, but Cloudflare proxies only the front end. The API (`api.<domain>`) is a DNS-only record, so it gets no Cloudflare WAF, rate limiting, or DDoS protection. The question was whether to add an API gateway (GCP API Gateway or Apigee) in front of Cloud Run.

## Decision
No API gateway. At launch, attach **Cloud Armor** to the global external Application Load Balancer for WAF (preconfigured OWASP rules), per-IP rate limiting, and L7 DDoS protection. FastAPI keeps token verification, per-user rate limiting, validation, and CORS. Cloud Run ingress is restricted to the load balancer so nothing bypasses Cloud Armor.

## Consequences
- Every gateway responsibility is covered without an extra hop or a second OpenAPI config to maintain.
- The API verifies users itself, which it must do anyway for object-level authorization.
- Cloud Armor adds ~US$7–10/month at launch.
- Pre-launch (no LB) there is no edge protection; auth and app-level rate limiting are the only defenses.

## Revisit when
There are multiple backend services needing one entry point, a public third-party API with API keys and quotas (possible with clinic/partner integrations after the rehab pivot), or protocol translation (e.g. gRPC → REST).
