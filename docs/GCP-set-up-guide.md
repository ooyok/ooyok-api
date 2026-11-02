# GCP Set-up Guide

Step-by-step provisioning for the ooyok API on GCP. Architecture and reasoning: [architecture-infra-guide.md](architecture-infra-guide.md).

- **Region:** `asia-east1` (Taiwan). Every regional resource uses the same region; change it via the Terraform `region` variable, never in code.
- **Projects:** `ooyok-staging` now, `ooyok-prod` **at launch**. Project IDs are globally unique, so replace `<staging-project-id>` / `<prod-project-id>` with the real IDs.
- **Repo:** `ooyok/ooyok-api` on GitHub.

> Steps 1–5 are one-time manual bootstrap (things that must exist before Terraform can run). Everything after is Terraform or CI.

## Contents
0. [Prerequisites](#0-prerequisites)
1. [Billing and budget](#1-billing-and-budget)
2. [Create the project](#2-create-the-project)
3. [Enable APIs](#3-enable-apis)
4. [Terraform state bucket](#4-terraform-state-bucket)
5. [GitHub Actions access (Workload Identity Federation)](#5-github-actions-access-workload-identity-federation)
6. [Firebase Authentication](#6-firebase-authentication)
7. [Provision with Terraform](#7-provision-with-terraform)
8. [First deploy](#8-first-deploy)
9. [Connect the front end](#9-connect-the-front-end)
10. [Launch settings (pre-launch → public release)](#launch-settings-pre-launch--public-release)
11. [Day-2 operations](#11-day-2-operations)

---

## 0. Prerequisites

Install locally: `gcloud` CLI, Terraform ≥ 1.9, Firebase CLI, Docker, `uv`, `just`.

```bash
gcloud auth login
gcloud auth application-default login
```

## 1. Billing and budget

Create (or reuse) a billing account in the console, then add a budget for **US$100/month** that alerts at 50%, 90%, and 100%:

```bash
gcloud billing accounts list
gcloud billing budgets create \
  --billing-account=<BILLING_ACCOUNT_ID> \
  --display-name="ooyok monthly" \
  --budget-amount=100USD \
  --threshold-rule=percent=0.5 \
  --threshold-rule=percent=0.9 \
  --threshold-rule=percent=1.0
```

A budget only alerts; it does not stop spending.

## 2. Create the project

```bash
gcloud projects create <staging-project-id> --name="ooyok staging"
gcloud billing projects link <staging-project-id> --billing-account=<BILLING_ACCOUNT_ID>
gcloud config set project <staging-project-id>
```

Repeat for `<prod-project-id>` **only at launch**.

## 3. Enable APIs

```bash
gcloud services enable \
  run.googleapis.com \
  sqladmin.googleapis.com \
  compute.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  pubsub.googleapis.com \
  cloudtasks.googleapis.com \
  cloudscheduler.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  cloudtrace.googleapis.com \
  firebase.googleapis.com \
  identitytoolkit.googleapis.com \
  --project=<staging-project-id>
```

## 4. Terraform state bucket

One bucket per project, with versioning so state can be recovered:

```bash
gcloud storage buckets create gs://<staging-project-id>-tfstate \
  --location=asia-east1 --uniform-bucket-level-access
gcloud storage buckets update gs://<staging-project-id>-tfstate --versioning
```

Reference it in `infra/terraform/envs/staging/backend.tf`:

```hcl
terraform {
  backend "gcs" {
    bucket = "<staging-project-id>-tfstate"
    prefix = "ooyok-api"
  }
}
```

## 5. GitHub Actions access (Workload Identity Federation)

No service-account JSON keys. GitHub's OIDC token is exchanged for short-lived GCP credentials.

```bash
PROJECT_ID=<staging-project-id>
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')

# Deployer service account
gcloud iam service-accounts create github-deployer --project=$PROJECT_ID

# Pool + provider, restricted to the ooyok/ooyok-api repo
gcloud iam workload-identity-pools create github \
  --location=global --project=$PROJECT_ID
gcloud iam workload-identity-pools providers create-oidc github-oidc \
  --location=global --workload-identity-pool=github --project=$PROJECT_ID \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
  --attribute-condition="assertion.repository=='ooyok/ooyok-api'"

# Let the repo impersonate the deployer
gcloud iam service-accounts add-iam-policy-binding \
  github-deployer@$PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github/attribute.repository/ooyok/ooyok-api"
```

Deployer roles (grant at project level; Terraform manages them after bootstrap):
`roles/run.admin`, `roles/artifactregistry.writer`, `roles/iam.serviceAccountUser` (on runtime SAs only), `roles/cloudsql.client` (for the migration job).

For prod, restrict further with `attribute.ref=='refs/heads/main'` and require a GitHub Environment approval.

## 6. Firebase Authentication

1. Firebase console → **Add project** → select the existing `<staging-project-id>` (Firebase attaches to the GCP project).
2. **Authentication → Sign-in method:** enable **Email/Password** and **Google**.
3. **Authentication → Settings → Authorized domains:** add the staging front-end domain (later the prod domain).
4. Register a **Web app** to get the front-end config (`apiKey`, `authDomain`, `projectId`). These values are public by design.
5. The API needs only the project ID (`FIREBASE_PROJECT_ID`). On Cloud Run, firebase-admin authenticates with the runtime service account; no key file.

## 7. Provision with Terraform

```bash
cd infra/terraform/envs/staging
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Terraform manages:

| Module | Resources |
|---|---|
| `network` | VPC `ooyok`, subnet in `asia-east1`, firewall: 6379 from the Cloud Run subnet → Redis VM only |
| `artifact_registry` | Docker repo `ooyok` (cleanup policy: keep last 20 images) |
| `cloud_sql` | Postgres 17, `db-f1-micro`, database `ooyok`, IAM database auth, backups on, deletion protection on |
| `redis_vm` | COS VM (`e2-micro`), no external IP, cloud-init running pinned `redis:<ver>-alpine`, `requirepass` from Secret Manager |
| `secrets` | `database-url`, `redis-url`, `redis-password` (values set out of band, never in tfvars) |
| `service_accounts` | `api-runtime`, `worker-runtime`, `pubsub-pusher`, `scheduler-invoker`; least-privilege bindings |
| `cloud_run_service` | `api` and `worker`, Direct VPC egress, Cloud SQL connection, secrets as env vars, `--cpu-boost` |
| `cloud_run_job` | `migrate` (Alembic), `outbox-relay` |
| `pubsub` | topic `domain-events`, push subscription → worker (OIDC), dead-letter topic after 5 attempts |
| `scheduler` | `outbox-relay` every minute, `idempotency-cleanup` daily |
| `monitoring` | uptime check, alert policies, dashboard |
| `load_balancer` | **only when `enable_lb = true`**: global external Application LB, serverless NEG, Google-managed certificate, Cloud Armor policy when `enable_cloud_armor = true` |

Set secret values once (example):

```bash
printf '%s' "<value>" | gcloud secrets versions add redis-password --data-file=-
```

## 8. First deploy

Pushing to `main` runs `deploy.yml`:

1. Build the image (tag = git SHA), push to `asia-east1-docker.pkg.dev/<project>/ooyok/api:<sha>`.
2. `gcloud run jobs execute migrate --wait`.
3. Deploy the `api` revision with `--no-traffic --tag=candidate`.
4. Smoke-test the candidate URL.
5. `gcloud run services update-traffic api --to-latest`.

Verify:

```bash
curl https://<api-service-url>/healthz
```

## 9. Connect the front end

The front end only knows **`NEXT_PUBLIC_API_BASE_URL`**. Pre-launch it points at the Cloud Run URL (or domain mapping). At launch you change this one value; no code changes.

API side, set `CORS_ALLOWED_ORIGINS` to the front-end origin(s).

---

## Launch settings (pre-launch → public release)

Everything that changes when you open to the public, in one place. Most items are Terraform variables in `infra/terraform/envs/<env>/terraform.tfvars`.

### Ingress options pre-launch (pick one)

| Option | Cost | Notes |
|---|---|---|
| Default `https://api-xxxx.a.run.app` | $0 | Simplest; no custom domain |
| Cloud Run **domain mapping** (`api-staging.<domain>` → Cloud Run) | $0 | Preview feature, not recommended by Google for production traffic. **Verify `asia-east1` is a supported region** before relying on it. The CNAME in the Cloudflare zone is **DNS-only (grey cloud)**, like every API record |
| Firebase Hosting rewrite → Cloud Run | ~$0 | Custom domain + CDN; fallback if domain mapping isn't available in the region |

### Settings table

| Setting | Where | Pre-launch | At launch | Why |
|---|---|---|---|---|
| Prod project exists | manual steps 2–6 + `envs/prod` | not created | created | biggest cost saver |
| `enable_lb` | `envs/prod/terraform.tfvars` | `false` | `true` | creates global external Application LB + serverless NEG + managed cert (~$18/mo) |
| `api_domain` | tfvars | `""` | `api.<domain>` | LB certificate + host |
| `cloud_run_ingress` | tfvars | `all` | `internal-and-cloud-load-balancing` | block direct `*.run.app` access so all traffic passes the LB + Cloud Armor |
| `api_min_instances` | tfvars | `0` | `1` | removes cold starts for real users |
| `api_max_instances` | tfvars | `3` | sized so `max × pool_size < DB max_connections` | protects the DB |
| `cloud_sql_tier` | tfvars | `db-f1-micro` | `db-g1-small` or a dedicated-core tier | shared-core has no SLA |
| `cloud_sql_availability_type` | tfvars | `ZONAL` | `ZONAL` (→ `REGIONAL` when justified; ~2× DB cost) | HA failover |
| `cloud_sql_pitr_enabled` | tfvars | `false` (staging) | `true` | point-in-time recovery |
| `cloud_sql_deletion_protection` | tfvars | `true` | `true` | — |
| `redis_machine_type` | tfvars | `e2-micro` | `e2-small` | headroom for cache + rate limiting |
| `enable_uptime_alerts` | tfvars | `false` | `true` | avoid alert noise before launch |
| DNS for `api.<domain>` | Cloudflare dashboard (the domain's zone) | absent, or DNS-only CNAME for domain mapping | **DNS-only (grey)** A record → LB IP. Never proxied | the API is not behind Cloudflare; the Google-managed certificate validates and renews against the LB IP |
| `enable_cloud_armor` | tfvars | `false` | `true` | attaches the Cloud Armor security policy to the LB backend service |
| `cloud_armor_rate_limit` | tfvars | — | e.g. 100 req/min per IP on `/v1/*`; ban 10 min on repeated abuse | per-IP abuse protection |
| `cloud_armor_waf_preview` | tfvars | — | `true` for the first days, then `false` | preconfigured OWASP rules (sqli, xss, lfi, rce) log-only first, then enforce, to avoid blocking real users |
| `NEXT_PUBLIC_API_BASE_URL` | front-end env | Cloud Run URL | `https://api.<domain>` | single switch on the client |
| `CORS_ALLOWED_ORIGINS` | API env / tfvars | staging front-end origin | prod front-end origin(s) | — |
| `DOCS_ENABLED` | API env | `true` | `false` | hide `/docs` in prod |
| Firebase authorized domains | Firebase console | staging domain | + prod domain | login redirects |
| GitHub Environment `prod` | GitHub repo settings | — | required reviewer on `promote.yml` | gated prod deploys |
| Budget | Billing | $100 | revisit with real traffic | — |

### Launch-day order
1. Create the prod project (steps 2–6).
2. `terraform apply` in `envs/prod` with `enable_lb = false`, `cloud_run_ingress = all`.
3. Promote the current staging image to prod; smoke-test the `*.run.app` URL.
4. Set `enable_lb = true`, `api_domain`, `enable_cloud_armor = true`, `cloud_armor_waf_preview = true`; apply.
5. Cloudflare: add an A record `api.<domain>` → LB IP, **DNS-only (grey)**.
6. Wait for the Google-managed certificate to become ACTIVE (can take up to ~1 h after DNS resolves to the LB IP).
7. Set `cloud_run_ingress = internal-and-cloud-load-balancing`, `api_min_instances = 1`, apply.
8. Switch the front end's `NEXT_PUBLIC_API_BASE_URL`; enable alerts; verify a restore drill was done.
9. After a few days, review Cloud Armor preview logs for false positives, then set `cloud_armor_waf_preview = false`.

---

## 11. Day-2 operations

| Task | How |
|---|---|
| Stop the staging DB when idle | `gcloud sql instances patch <instance> --activation-policy=NEVER` (start: `ALWAYS`) |
| Roll back a bad deploy | `gcloud run services update-traffic api --to-revisions=<previous-revision>=100` |
| Upgrade Redis | bump `redis_image_tag` in tfvars → `terraform apply` (VM recreated, ~1 min of cache misses; app fails open) |
| Resize Redis | change `redis_machine_type` → `terraform apply` |
| Redis OS patches | automatic on COS; applied on reboot |
| Check Redis health | Cloud Monitoring dashboard: memory, evictions, connections |
| Rotate a secret | add a new version in Secret Manager → redeploy (or reference `latest`) |
| Run a migration manually | `gcloud run jobs execute migrate --region=asia-east1 --wait` |
| Inspect the outbox backlog | alert "outbox lag"; `SELECT count(*) FROM outbox WHERE published_at IS NULL` |
| Review Cloud Armor blocks | Logs Explorer → load balancer request logs, filter on `jsonPayload.enforcedSecurityPolicy` |
| Move Redis to Memorystore | create the instance, update the `redis-url` secret, redeploy, delete the VM |
