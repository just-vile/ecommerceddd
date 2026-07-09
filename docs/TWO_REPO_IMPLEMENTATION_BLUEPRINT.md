# EcommerceDDD Two-Repo Implementation Blueprint

Author: DevOps Engineering  
Scope: Implement Kubernetes + CI/CD with two repositories:
- Repository A: Application code
- Repository B: GitOps (with two top-level folders: platform and apps)
Status: Draft v1

---

## 1. Target Repository Model

## Repository A: EcommerceDDD (application source)
Purpose:
- Own service code, tests, Dockerfiles
- Build, test, scan, sign, and publish container images
- Propose deployment changes into Repository B

Primary responsibilities:
- .NET and SPA code changes
- Unit and integration tests
- Image build and vulnerability scanning
- SBOM generation and image signing
- Automatic image tag update PRs to Repository B apps folder

## Repository B: EcommerceDDD-gitops (deployment source of truth)
Purpose:
- Own all cluster deployment intent for platform and applications
- Feed Argo CD pull-based reconciliation

Top-level folders:
- platform: cluster-level shared components
- apps: business workloads and environment overlays

Primary responsibilities:
- Platform operators and shared infrastructure manifests/charts
- App Helm charts and environment-specific values
- Argo CD application definitions (two standalone apps)
- Dev-only GitOps workflow (staging/prod deferred, no resource creation)

---

## 2. Detailed Repository Structures

## 2.1 Repository A structure (EcommerceDDD)

Suggested structure additions in the existing repository:

- .github/
  - workflows/
    - ci-build-test.yml
    - ci-images-matrix.yml
    - ci-security-sbom-sign.yml
    - ci-update-gitops-dev.yml
    - ci-release-tag.yml
  - actions/
    - setup-dotnet-node/
    - docker-build-push/
    - create-gitops-pr/
- build/
  - matrix-services.json
  - scripts/
    - build-images.ps1
    - scan-images.ps1
    - sign-images.ps1
- deployment/
  - contracts/
    - image-tag-schema.json
    - app-values-contract.md
- src/
  - existing source code
- docs/
  - KUBERNETES_CICD_MIGRATION_PLAN.md
  - TWO_REPO_IMPLEMENTATION_BLUEPRINT.md

Notes:
- Keep this repository free of cluster manifests except optional development examples.
- Only CI metadata and deployment contracts stay here.

## 2.2 Repository B structure (EcommerceDDD-gitops)

Root layout:

- platform/
  - bootstrap/
    - namespaces/
    - argo-cd-install/
    - argocd-apps/
      - platform-app.yaml
      - apps-dev-app.yaml
  - ingress-nginx/
    - base/
    - overlays/
      - dev/
      - README.md
  - external-secrets/
    - base/
    - stores/
      - dev/
      - README.md
  - cnpg/
    - operator/
    - clusters/
      - dev/
      - README.md
    - backup-policies/
  - strimzi/
    - operator/
    - kafka/
      - dev/
      - README.md
    - connect/
    - topics/
  - observability/
    - otel-collector/
    - prometheus/
    - grafana/
    - loki-tempo/
  - policies/
    - pod-security/
    - network-policy-defaults/
    - image-policy/
  - projects/
    - argo-projects.yaml

- apps/
  - charts/
    - ecommerceddd-service/
      - Chart.yaml
      - values.yaml
      - templates/
        - deployment.yaml
        - service.yaml
        - configmap.yaml
        - secret-ref.yaml
        - hpa.yaml
        - pdb.yaml
        - networkpolicy.yaml
        - serviceaccount.yaml
        - ingress.yaml
        - servicemonitor.yaml
    - ecommerceddd-apigateway/
    - ecommerceddd-identityserver/
    - ecommerceddd-signalr/
    - ecommerceddd-spa/
  - environments/
    - dev/
      - values/
        - customer-management.yaml
        - product-catalog.yaml
        - inventory-management.yaml
        - quote-management.yaml
        - order-processing.yaml
        - payment-processing.yaml
        - shipment-processing.yaml
        - apigateway.yaml
        - identityserver.yaml
        - signalr.yaml
        - spa.yaml
      - ingress/
      - secrets/
      - kustomization.yaml
    - README.md
  - argocd/
    - apps/
      - dev/
      - README.md
    - appsets/
      - core-apps.yaml
      - preview-apps.yaml

- environments/
  - dev/
    - promotion-policy.yaml
  - README.md

- .github/
  - workflows/
    - validate-manifests.yml
    - helm-lint.yml
    - policy-checks.yml
    - dev-sync-guardrails.yml

- scripts/
  - bootstrap-minikube.ps1
  - validate-render.ps1
  - bump-image-tag.ps1

- docs/
  - runbooks/
  - incident-response/
  - rollback-guide.md

---

## 3. Argo CD Application Topology in Repository B

## 3.1 Two-Application Topology

Argo CD runs two independent applications:
- `platform` application group
- `apps-dev` application group

Each application manages its own subtree:
- Platform app manages platform components
- Apps-dev app manages business services in dev

Sync strategy:
- platform first (wave 0)
- shared data services next (wave 1)
- application services next (wave 2)
- edge services and SPA last (wave 3)

Operational rule:
- Sync `platform` first, then sync `apps-dev`.
- If `platform` is degraded, pause `apps-dev` sync.

## 3.2 Recommended Argo projects

- project-platform
  - Allowed source paths: platform/*
  - Allowed destination namespaces: platform, data
- project-apps
  - Allowed source paths: apps/*
  - Allowed destination namespaces: ecom-dev

This prevents accidental app deployment into platform namespaces.

---

## 4. CI/CD Split of Responsibilities

## 4.1 Repository A pipelines

Pipeline 1: ci-build-test.yml
- Trigger: pull request, push to main
- Steps:
  - Restore/build/test .NET solution
  - Run SPA unit tests
  - Optional contract tests

Pipeline 2: ci-images-matrix.yml
- Trigger: push to main, tagged release
- Steps:
  - Build images for 11 components in matrix
  - Push immutable tags sha-<shortsha> to registry

Pipeline 3: ci-security-sbom-sign.yml
- Trigger: after image build
- Steps:
  - Trivy scan
  - Generate SBOM
  - Cosign sign

Pipeline 4: ci-update-gitops-dev.yml
- Trigger: all image build jobs successful
- Steps:
  - Clone Repository B
  - Update apps/environments/dev/values/*.yaml image tags
  - Create pull request to Repository B main

## 4.2 Repository B pipelines

Pipeline 1: validate-manifests.yml
- Trigger: pull request
- Steps:
  - Helm lint
  - Template render for dev namespace on Minikube
  - Kubeconform validation

Pipeline 2: policy-checks.yml
- Trigger: pull request
- Steps:
  - Conftest or Kyverno policy checks
  - Ensure no latest tags
  - Ensure resource limits and probes exist

Pipeline 3: dev-sync-guardrails.yml
- Trigger: manual dispatch or scheduled
- Steps:
  - Validate dev overlays, secrets naming, and immutable tags
  - Emit readiness report for future staged promotion

Argo CD deploys only from Repository B merges.

---

## 5. Branching and Environment Strategy

Repository A:
- main: production-ready source
- feature/*: developer branches
- release/*: optional controlled release

Repository B:
- main: desired deployed state
- change/*: dev deployment changes and platform updates

Environment mapping:
- apps/environments/dev -> auto-sync enabled
- staging/prod -> deferred (no namespace or resource creation)

Protection rules:
- Require reviews on main in both repositories
- Require status checks in both repositories
- Require signed commits for deployment PRs if possible

---

## 6. Versioning Contract Between Repositories

Use immutable deployment tuple:
- image tag: sha-<gitsha>
- chart version: semantic version for templates
- environment values revision: git commit hash in Repository B

Rules:
- Never deploy floating tags in dev
- Keep immutable tags in dev; future environment promotion is deferred
- Chart updates and image updates should be isolated in separate PRs when possible

Recommended metadata labels in every deployment:
- app.kubernetes.io/name
- app.kubernetes.io/version
- app.kubernetes.io/managed-by
- ecommerceddd.io/source-repo
- ecommerceddd.io/source-sha
- ecommerceddd.io/gitops-repo
- ecommerceddd.io/gitops-sha

---

## 7. Secrets and Configuration Ownership

Repository A owns:
- Config contract documentation (which env vars each service requires)

Repository B owns:
- Non-secret environment config values
- Secret references (not secret plaintext)

Development (local minikube):
- Pre-created Kubernetes Secrets allowed

Staging and production:
- Deferred (do not create namespaces or resources in this phase)

Guardrails:
- Block PR if plaintext secrets detected
- Block PR if appsettings secrets are copied into values files

---

## 8. Platform and App Rollout Order

Phase 0: Foundation
- Create Repository B
- Install Argo CD manually once
- Apply two Argo CD applications: `platform-app.yaml` and `apps-dev-app.yaml`

Phase 1: Platform baseline in Repository B platform folder
- ingress-nginx
- cnpg operator
- strimzi operator
- otel collector and metrics stack

Phase 2: App baseline in Repository B apps folder
- Generic chart
- Service-specific chart wrappers
- Dev environment values and ingress

Phase 3: Repository A automation
- Build and push matrix images
- Security and signing
- Auto PR into Repository B dev values

Phase 4: Promotion
- Keep implementation dev-only
- Add documentation placeholders for future staging/prod
- Do not create staging/prod namespaces or resources

---

## 9. Ownership Model (RACI-lite)

Platform Team:
- Owns Repository B platform folder
- Approves operator and policy changes

Application Platform Team:
- Owns Repository B apps charts and environment overlays
- Approves app deployment model changes

Service Teams:
- Own Repository A service code
- Approve image and code changes

Release Manager or SRE:
- Approves deployment governance changes for dev phase

---

## 10. Minimum Implementation Backlog

Epic A: Repository B bootstrap
1. Create repository skeleton
2. Add two Argo CD applications (`platform` and `apps-dev`)
3. Add platform bootstrap manifests

Epic B: App deployability
1. Create generic service chart
2. Add values for all 11 components in dev
3. Add ingress routes and probes

Epic C: Repository A deployment automation
1. Add matrix image build workflow
2. Add scan and SBOM workflow
3. Add gitops update PR workflow

Epic D: Promotion and governance
1. Add dev-only governance checks and documentation placeholders for staging/prod
2. Add policy checks
3. Add future promotion design notes only (no deployment workflows)

---

## 11. Operational Runbooks to Prepare Early

Required runbooks in Repository B docs folder:
- Argo CD sync failure triage
- Rollback by reverting values tag
- CNPG restore drill
- Kafka broker recovery
- Secret rotation process
- Emergency freeze process for prod sync

---

## 12. Definition of Done for Two-Repo Model

The model is considered successfully implemented when:
1. A merge in Repository A publishes signed images and creates a PR in Repository B dev values.
2. A merge in Repository B automatically syncs dev via Argo CD and health checks pass.
3. No staging/prod namespaces or resources are created during this phase.
4. Platform changes are isolated to Repository B platform folder and cannot be modified by app-only pipelines.
5. Rollback can be completed by a single revert PR in Repository B.

---

## 13. Key Trade-off Summary for Two-Repo Model

What you gain:
- Better separation than monorepo deployment
- Lower operational friction than three repositories
- Clear GitOps boundary with manageable coordination cost

What you accept:
- Some cross-repo orchestration complexity
- Need for strict version contracts and automation discipline

This is the recommended balance for your current migration phase.
