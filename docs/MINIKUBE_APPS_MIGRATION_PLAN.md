# Plan: Land EcommerceDDD app services on Minikube (dev)

## TL;DR
Platform (Argo CD, ingress-nginx, CNPG Postgres, Strimzi Kafka+Connect, OTel) is live in
minikube. This plan adds the `apps/` tree to the existing `EcommerceDDD-gitops` repo,
containerizes the 11 workloads (7 domain services + IdentityServer + ApiGateway + SignalR
+ SPA), publishes images to GHCR, and drives rollout to the `ecom-dev` namespace through
a single Argo CD `ApplicationSet` (project-apps). Uses **Kustomize base + per-service
overlays** (chart strategy chosen by user). SPA is converted to runtime config so the
image is env-agnostic. No staging/prod resources are created.

## Scope
Included:
- All 11 workloads to `ecom-dev` on minikube (dev namespace only)
- Kustomize `apps/base` + `apps/overlays/dev` in gitops repo
- Argo CD `ApplicationSet` (project-apps) wiring
- GHCR image pipeline (source repo) with per-merge overlay tag bump PR
- SPA runtime-config conversion (source repo)
- Ingress hostnames, TLS, image pull secret, service-side Secrets bootstrap
- Smoke test + rollback drill

Excluded:
- Any staging/prod resources
- Argo Rollouts / canary
- Cosign admission enforcement
- Redis SignalR backplane (single replica for dev)

---

## Phase M1 — Source-repo prep (this repo)

Runs in `EcommerceDDD` (Repository A). Independent from platform.

1. **Dockerfile hygiene (11 files)** — enforce non-root user, install `curl` only in
   images that use it, add `LABEL org.opencontainers.image.source=...`, prune build
   context via `.dockerignore` (bin/, obj/, node_modules/, .git/, **/*.user, tests/).
   Files: every path under `src/**/Dockerfile` and `src/EcommerceDDD.Spa/Dockerfile`.
2. **SPA runtime config** — replace build-time `environment.ts` constants with a runtime
   fetch of `/assets/config.json` at bootstrap. Nginx serves the file from a directory
   backed by a K8s ConfigMap volume in dev. Files:
   - `src/EcommerceDDD.Spa/src/environments/environment.ts` and `environment.prod.ts` →
     strip URL values, keep `production` flag only
   - Add `src/EcommerceDDD.Spa/src/app/config/app-config.service.ts` — loads JSON at
     `APP_INITIALIZER`
   - Update DI provider list (usually in `src/EcommerceDDD.Spa/src/app/app.config.ts`)
     to inject the service in HTTP interceptors / SignalR client
   - Update `src/EcommerceDDD.Spa/nginx.conf` to also serve `/assets/config.json` with
     `no-cache`
3. **Reusable build workflow** — `.github/workflows/build-image.yml` (workflow_call).
   Inputs: `service`, `context`, `dockerfile`. Steps: buildx, cache=gha, tag
   `ghcr.io/<org>/ecommerceddd-<service>:sha-${SHORTSHA}` + `:main-latest`, push. Uses
   `permissions: { packages: write, id-token: write, contents: read }`, no PAT.
4. **Matrix caller workflow** — `.github/workflows/ci-images.yml`. Trigger on push to
   `main`. Matrix over 11 entries (from `build/matrix-services.json`). Depends on
   existing `ecommerceddd-build.yml` completing green.
5. **GitOps updater workflow** — `.github/workflows/update-gitops-dev.yml`. Runs after
   matrix build. Checks out `EcommerceDDD-gitops` with a fine-scoped GitHub App token,
   runs `yq` to set `.images[?(@.name=="<service>")].newTag = "sha-<sha>"` in
   `apps/overlays/dev/kustomization.yaml`, opens a PR titled
   `chore(dev): bump <service> to sha-<sha>`. All 11 updates land in a single PR per
   merge to keep atomicity.

---

## Phase M2 — Gitops-repo `apps/` scaffold

Runs in `EcommerceDDD-gitops` (Repository B) under the new `apps/` tree.

Structure:
```
apps/
  base/
    dotnet-service/            # generic base for .NET service
      kustomization.yaml
      deployment.yaml          # non-root, probes, resources, envFrom
      service.yaml             # ClusterIP:80 → containerPort 8080
      serviceaccount.yaml
      configmap.yaml           # ASPNETCORE_URLS, OTEL endpoint, log levels
      networkpolicy.yaml       # default-deny + allow-from-apigateway/dns/data
      hpa.yaml                 # cpu 60%, min=1 max=3 for dev
      pdb.yaml                 # minAvailable: 1
    spa/
      kustomization.yaml
      deployment.yaml          # nginx-unprivileged
      service.yaml
      configmap.yaml           # holds runtime `config.json` as data
  overlays/
    dev/
      kustomization.yaml       # aggregates all services, sets `images:` (11 tags)
      namespace.yaml           # references existing ecom-dev, adds labels
      common/
        image-pull-secret-note.md   # doc for manual `kubectl create secret`
        env-config.yaml         # cluster-DNS ConfigMap consumed by envFrom
      services/
        customer-management/{kustomization.yaml, patch.yaml}
        product-catalog/…
        inventory-management/…
        quote-management/…
        order-processing/…
        payment-processing/…
        shipment-processing/…
        identityserver/…
        apigateway/…
        signalr/…
        spa/…
      ingress/
        apigateway-ingress.yaml
        identityserver-ingress.yaml
        signalr-ingress.yaml   # WebSocket + affinity annotations
        spa-ingress.yaml
  argocd/
    project-apps.yaml          # if not already created by platform track
    apps-dev-appset.yaml       # ApplicationSet, one Application per service overlay
```

Per-service overlay pattern (`services/<name>/kustomization.yaml`):
- `resources: [../../../../base/dotnet-service]` (or `../base/spa` for SPA)
- `namePrefix: ` empty (names come from patches for exactness)
- `nameSuffix: ""`
- `commonLabels: { app.kubernetes.io/name: ecommerceddd-<name> }`
- `configMapGenerator` for service-specific settings (e.g., service URLs, connection
  string template with `postgres.data.svc.cluster.local`, Kafka bootstrap DNS)
- `patches:` set container name, ports, service DNS, probes' path
- `images:` empty (image tag comes from top-level `overlays/dev/kustomization.yaml`)

Top-level `overlays/dev/kustomization.yaml`:
- `resources:` lists all 11 service overlays + common configmap + ingresses
- `namespace: ecom-dev`
- `images:` — 11 entries mapping name → `ghcr.io/<org>/ecommerceddd-<svc>` + `newTag`
  (updated by CI PR)
- `commonAnnotations: { ecommerceddd.io/gitops-sha: "$Format:%H$" }`

Argo `ApplicationSet` (`apps/argocd/apps-dev-appset.yaml`):
- Generator: `list` of 11 service names with per-item sync-wave (below)
- Template creates one `Application` per service:
  - `project: project-apps`
  - `source.repoURL: <gitops-repo>`
  - `source.path: apps/overlays/dev/services/<name>`
  - `source.kustomize.commonAnnotations` merges parent tag from overlay
  - `destination: { namespace: ecom-dev }`
  - `syncPolicy: automated { prune: true, selfHeal: true }` + `retry`
  - `annotations: { argocd.argoproj.io/sync-wave: "<wave>" }`

Alternative (simpler): a single Argo `Application` pointing at
`apps/overlays/dev`. Recommended — single sync graph, easier rollback. Waves are then
set per-resource via `argocd.argoproj.io/sync-wave` annotation on each Deployment. Use
this unless later you need PR previews via ApplicationSet.

Sync-wave ordering inside `apps-dev`:
- Wave 0: ConfigMaps, Secrets refs, ServiceAccounts, NetworkPolicies
- Wave 1: `identityserver`
- Wave 2: `product-catalog`
- Wave 3: `customer-management`, `inventory-management`, `quote-management`
- Wave 4: `order-processing`, `payment-processing`, `shipment-processing`
- Wave 5: `signalr`, `apigateway`
- Wave 6: `spa`
- Wave 7: `Ingress` resources

---

## Phase M3 — Configuration & Secrets mapping

**Cluster DNS mapping (ConfigMap `apps/overlays/dev/common/env-config.yaml`):**
| App env var (double-underscore) | Value |
|---|---|
| `ConnectionStrings__DefaultConnection` | template with host `ecom-postgres-rw.data.svc.cluster.local`, per-service database name |
| `KafkaConsumer__ConnectionString` | `ecom-kafka-kafka-bootstrap.data.svc.cluster.local:9092` |
| `DebeziumSettings__ConnectorUrl` | `http://ecom-connect-connect-api.data.svc.cluster.local:8083/connectors/<svc>-connector` |
| `DebeziumSettings__DatabaseHostname` | `ecom-postgres-rw.data.svc.cluster.local` |
| `Services__<Peer>` | `http://ecommerceddd-<peer>.ecom-dev.svc.cluster.local` |
| `TokenIssuerSettings__Authority` | **`http://id.dev.ecommerceddd.local`** (ingress host — required so browser-issued tokens match backend audience) |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://otel-collector.platform.svc.cluster.local:4317` |
| `ASPNETCORE_URLS` | `http://+:8080` (align with non-root container port) |

**Pre-created dev Secrets** (documented in `apps/overlays/dev/common/image-pull-secret-note.md` — bootstrap commands only, values never committed):
- `ecom-dev-ghcr` (`kubernetes.io/dockerconfigjson`) — image pull secret, referenced by all 11 ServiceAccounts.
- `ecom-dev-postgres-app` — per-service DB password (mounted key `PGPASSWORD` merged into connection string via env template + `stringData`).
- `ecom-dev-identityserver` — `TokenIssuerSettings__ClientSecret`, IdentityServer signing key.
- `ecom-dev-kafka-sasl` — placeholder, only if SASL is enabled later.

Runbook creates them once via `kubectl create secret …` before first sync.

---

## Phase M4 — Ingress & DNS

`ingress-nginx` already installed by platform track. Add hosts to
`C:\Windows\System32\drivers\etc\hosts` (or resolve via `minikube tunnel`):
```
127.0.0.1 api.dev.ecommerceddd.local
127.0.0.1 app.dev.ecommerceddd.local
127.0.0.1 id.dev.ecommerceddd.local
127.0.0.1 hub.dev.ecommerceddd.local
```
TLS via mkcert into K8s Secret `ecom-dev-tls-wildcard` (`*.dev.ecommerceddd.local`).
SignalR ingress must set:
- `nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"`
- `nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"`
- `nginx.ingress.kubernetes.io/affinity: "cookie"`

---

## Phase M5 — Rollout

1. Merge M1 to `main` — CI builds+pushes all 11 images with `sha-<X>` and opens
   bump PR against gitops repo.
2. Reviewer merges bump PR. Argo CD detects change, syncs waves 0-7. Blocked syncs
   surface via Argo UI (`argocd app list`).
3. Post-sync `Job` in wave 0 runs `scripts/db_init.sql` against CNPG (creates
   `identityserverdb`, `customersdb`, `productsdb`, `inventorydb`, `quotesdb`,
   `ordersdb`, `paymentsdb`, `shipmentsdb`). Idempotent — skips if schema exists.
4. Health check via ingress hosts:
   - `curl -k https://api.dev.ecommerceddd.local/health`
   - `curl -k https://id.dev.ecommerceddd.local/health`
   - SPA in browser at `https://app.dev.ecommerceddd.local`

---

## Relevant files
Source repo (this workspace):
- `src/**/Dockerfile` (11 files) — hygiene + labels
- `src/EcommerceDDD.Spa/src/environments/*.ts` — strip URLs
- `src/EcommerceDDD.Spa/src/app/config/app-config.service.ts` — new
- `src/EcommerceDDD.Spa/src/app/app.config.ts` — register APP_INITIALIZER
- `src/EcommerceDDD.Spa/nginx.conf` — serve `/assets/config.json` no-cache
- `.github/workflows/build-image.yml` — new reusable
- `.github/workflows/ci-images.yml` — new matrix caller
- `.github/workflows/update-gitops-dev.yml` — new bump PR
- `build/matrix-services.json` — new; 11 rows: service, context, dockerfile
- `scripts/db_init.sql` — reuse; wrap into K8s Job manifest in gitops repo

Gitops repo (EcommerceDDD-gitops):
- `apps/base/dotnet-service/*`
- `apps/base/spa/*`
- `apps/overlays/dev/kustomization.yaml`
- `apps/overlays/dev/services/**/kustomization.yaml`
- `apps/overlays/dev/services/**/patch.yaml`
- `apps/overlays/dev/common/env-config.yaml`
- `apps/overlays/dev/ingress/*.yaml`
- `apps/argocd/apps-dev-app.yaml` (single Application) or `apps-dev-appset.yaml`
- `apps/argocd/project-apps.yaml` (if not already on platform side)

---

## Verification
1. `dotnet build EcommerceDDD.sln` still green (no code regressions from SPA changes).
2. `kubectl -n ecom-dev get pods` — all 11 workloads `Running` with ready `2/2` (app + istio sidecar N/A here, so `1/1`).
3. `kubectl -n ecom-dev get events --sort-by=.lastTimestamp | tail -50` — no
   `ImagePullBackOff`, `CreateContainerConfigError`.
4. `argocd app list -p project-apps` — every app `Synced/Healthy`.
5. `curl -kfsS https://api.dev.ecommerceddd.local/health` → 200; same for `id.…/health`.
6. Browser login flow at `https://app.dev.ecommerceddd.local` completes; JWT `iss`
   claim matches `id.dev.ecommerceddd.local`.
7. Place an order end-to-end; verify `orders` topic messages in Kafka UI and read models
   populated in Postgres.
8. Distributed trace visible in OTel collector → configured backend for one order flow.
9. **Rollback drill**: `git revert` the bump PR in gitops repo → Argo re-syncs previous
   `sha-…` tag in <2 minutes. Pods roll back cleanly.
10. **NetworkPolicy check**: from a temporary pod in `ecom-dev`, direct calls to
    `product-catalog` succeed only from `apigateway`/allowed peers, blocked from
    unrelated namespaces.

---

## Decisions locked in from clarification
- Gitops repo `EcommerceDDD-gitops` exists; platform track completed there. This plan
  adds the `apps/` tree only.
- Images built locally by CI, pushed to GHCR, pulled by minikube via `ecom-dev-ghcr`
  imagePullSecret bound to each ServiceAccount.
- SPA included — 11 workloads total.
- **Kustomize base + per-service overlays** (no Helm), per user selection.

## Further considerations
1. **Argo topology**: single `Application` for `apps/overlays/dev` (simpler, atomic
   rollback) vs `ApplicationSet` (better isolation, needed later for PR previews).
   *Recommend single Application now; migrate to ApplicationSet when PR previews land.*
2. **Postgres access model**: shared `postgres` superuser (matches current compose)
   vs one CNPG `Database`/role per service. *Recommend per-service databases now
   (already implied by current DB names) but keep the superuser for M5 to minimize
   moving parts; split roles as a follow-up.*
3. **SPA config injection**: nginx ConfigMap volume (chosen above) vs a small init-
   container that writes `config.json` from env. *Recommend ConfigMap volume — no
   custom entrypoint, easy to review in GitOps.*
