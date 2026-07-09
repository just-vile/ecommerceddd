# EcommerceDDD Platform GitOps Implementation Plan (Minikube)

Author: DevOps Engineering  
Scope: Implement the platform layer in Repository B (EcommerceDDD-gitops) for Minikube-based environments.  
Status: Draft v1

---

## 1. Objective

Build and operate the platform portion of the GitOps repository so Argo CD can continuously reconcile shared cluster components required by all application services.

Platform scope includes:
- Namespace and baseline cluster bootstrap
- Argo CD installation and App-of-Apps root wiring
- ingress-nginx and dev TLS secret bootstrap
- CloudNativePG operator and Postgres clusters
- Strimzi operator, Kafka, KafkaConnect, topics
- Observability baseline (OTel Collector + Prometheus/Grafana)
- Platform policies and Argo project boundaries

Implementation boundary in this phase:
- Deploy platform resources in `dev` scope only.
- Do not create any `staging` or `prod` platform resources.

Out of scope for this plan:
- Service-specific charts and environment values (apps folder)
- Business workload rollout

---

## 2. Target Repository Layout (platform only)

Target in Repository B root:

```text
platform/
  bootstrap/
    namespaces/
      namespaces.yaml
    argo-cd-install/
      kustomization.yaml
      helm-values.yaml
    root-app/
      root-application.yaml

  projects/
    argo-projects.yaml

  ingress-nginx/
    base/
      kustomization.yaml
      helmrelease-or-manifests.yaml
    overlays/
      dev/
      README.md

  cnpg/
    operator/
    clusters/
      dev/
      README.md
    bootstrap/
      db-init-job.yaml
    backup-policies/

  strimzi/
    operator/
    kafka/
      dev/
      README.md
    connect/
      dev/
      README.md
    topics/
      dev/
      README.md

  observability/
    otel-collector/
      base/
      overlays/
        dev/
        README.md
    prometheus/
      base/
      overlays/
        dev/
        README.md
    grafana/
      base/
      overlays/
        dev/
        README.md

  policies/
    pod-security/
    network-policy-defaults/
    image-policy/

  docs/
    runbooks/
      platform-bootstrap.md
      platform-upgrade.md
      platform-rollback.md
```

---

## 3. Argo CD Topology for Platform

## 3.1 App hierarchy

- Root Application
  - Platform Aggregator Application
    - Namespace bootstrap app
    - Argo projects app
    - ingress-nginx app
    - cnpg operator app
    - cnpg clusters app
    - strimzi operator app
    - strimzi kafka/connect/topics app
    - observability apps
    - platform policies app

## 3.2 Sync waves

Use Argo CD sync-wave annotations to guarantee order:

- Wave 0: namespaces, argo projects
- Wave 1: ingress-nginx
- Wave 2: cnpg operator, strimzi operator
- Wave 3: cnpg clusters, kafka clusters, connect
- Wave 4: topics, observability stack
- Wave 5: policies (if policy engine can enforce safely at this stage)

## 3.3 Argo project boundaries

- project-platform
  - sourceRepos: only GitOps repo
  - destinations: platform, data namespaces
  - clusterResourceWhitelist: explicit allowlist

- project-apps
  - sourceRepos: same GitOps repo
  - destinations: ecom-dev

This prevents platform manifests from leaking into application namespaces and vice versa.

---

## 4. Implementation Phases

## Phase A: Bootstrap Foundation

Goal: establish base namespaces, Argo CD root wiring, and project boundaries.

Tasks:
1. Create namespace bootstrap manifest for:
   - platform
   - data
   - ecom-dev
2. Add labels for Pod Security baseline by namespace.
3. Create Argo project definitions (project-platform, project-apps).
4. Create root application manifest pointing to platform and apps aggregators.
5. Validate Argo CD can reconcile root app successfully.

Deliverables:
- platform/bootstrap/namespaces/namespaces.yaml
- platform/projects/argo-projects.yaml
- platform/bootstrap/root-app/root-application.yaml

Acceptance criteria:
- All namespaces exist and labeled.
- Argo root app is Synced and Healthy.

## Phase B: Networking and Secret Foundations

Goal: deploy ingress, TLS mechanism, and the dev secret bootstrap process.

Tasks:
1. Add ingress-nginx base manifests/helm values.
2. Document `mkcert`-based TLS secret creation for dev ingress hosts.
3. Document the required pre-created Kubernetes Secrets for platform dependencies.
4. Validate secret bootstrap commands against the dev cluster.

Deliverables:
- platform/ingress-nginx/base/*

Acceptance criteria:
- Ingress controller Running.
- Dev TLS secret workflow documented and usable for ingress hosts.
- Required platform Secrets can be created out of band before sync.

## Phase C: Data Platform (Postgres + Kafka)

Goal: provide stateful platform dependencies used by microservices.

Tasks:
1. Install CNPG operator.
2. Add per-environment CNPG cluster definitions in data namespace.
3. Add DB bootstrap job for schema initialization.
4. Install Strimzi operator.
5. Add per-environment Kafka cluster definitions (KRaft mode).
6. Add KafkaConnect definitions for Debezium connectors.
7. Add required topic manifests for payments, shipments, orders.

Deliverables:
- platform/cnpg/operator/*
- platform/cnpg/clusters/dev/*
- platform/cnpg/bootstrap/db-init-job.yaml
- platform/strimzi/operator/*
- platform/strimzi/kafka/dev/*
- platform/strimzi/connect/dev/*
- platform/strimzi/topics/dev/*

Acceptance criteria:
- CNPG cluster Ready in dev model.
- Kafka brokers Ready and topics visible.
- KafkaConnect Ready with connector CRs accepted.

## Phase D: Observability Platform

Goal: deploy shared telemetry plumbing.

Tasks:
1. Deploy OTel Collector base with OTLP ingest.
2. Deploy Prometheus stack baseline.
3. Deploy Grafana baseline and seed starter dashboards.
4. Add dev overlay for retention and resource sizing.
5. Add ServiceMonitor defaults for platform components.

Deliverables:
- platform/observability/otel-collector/*
- platform/observability/prometheus/*
- platform/observability/grafana/*

Acceptance criteria:
- OTel Collector receives test traces.
- Prometheus targets healthy.
- Grafana accessible through ingress.

## Phase E: Guardrails and Policy

Goal: establish platform security and operational controls.

Tasks:
1. Add default deny network policy templates in platform and data namespaces.
2. Add baseline pod security policies/manifests.
3. Add image tag policy (disallow latest in platform workloads).
4. Add Argo sync window and freeze mechanism for change control.
5. Add platform-level resource quotas and limit ranges where appropriate.

Deliverables:
- platform/policies/pod-security/*
- platform/policies/network-policy-defaults/*
- platform/policies/image-policy/*

Acceptance criteria:
- Policy checks pass in CI.
- No platform workload runs with latest tag.
- Default deny policy enforced with explicit allows.

---

## 5. CI/CD for Platform Folder

## 5.1 Required workflows in GitOps repo

1. validate-platform-manifests.yml
- Trigger: PR touching platform/**
- Steps:
  - Kustomize build for dev overlay
  - Helm lint/template where applicable
  - kubeconform validation

2. platform-policy-checks.yml
- Trigger: PR touching platform/**
- Steps:
  - Conftest/Kyverno policy tests
  - naming convention checks
  - sync-wave annotation presence checks

3. platform-drift-check.yml (optional)
- Scheduled
- Steps:
  - Query Argo app health and sync status
  - Report drift summary artifact

## 5.2 PR gates

Require all checks below before merge:
- manifest validation success
- policy checks success
- security scan of modified manifests (if integrated)
- approval from platform code owners

---

## 6. Naming and Versioning Standards

## 6.1 App names (Argo)

Pattern:
- platform-<component>-<env>

Examples:
- platform-ingress-dev
- platform-cnpg-operator
- platform-kafka-dev

## 6.2 Resource naming

Pattern:
- ecom-<component>-<env>

Examples:
- ecom-postgres-dev
- ecom-kafka-dev

## 6.3 Version pinning

- Pin chart versions explicitly.
- Pin container tags explicitly (no floating latest).
- Upgrade operators by dedicated PRs with release notes.

---

## 7. Rollout Strategy (Dev-only)

1. Dev namespace rollout
- Deploy and stabilize platform changes in dev scope first.

2. Deferred namespaces
- Keep staging/prod as documentation placeholders only.
- Do not create staging/prod platform resources in this phase.

---

## 8. Operational Runbooks to Add During Implementation

Create and maintain these runbooks under platform/docs/runbooks:

1. platform-bootstrap.md
- first install and recovery bootstrap steps

2. platform-upgrade.md
- operator/chart upgrade steps and rollback checkpoints

3. platform-rollback.md
- rollback by Git revert and Argo sync strategy

4. cnpg-recovery.md
- Postgres fail/recover checklist

5. strimzi-recovery.md
- Kafka and connect failure recovery checklist

6. ingress-tls-rotation.md
- local cert rotation and TLS secret handling

---

## 9. Risks and Mitigations

1. Single-cluster blast radius
- Risk: platform change impacts all env namespaces.
- Mitigation: keep implementation dev-only and defer staging/prod rollout.

2. Resource pressure on Minikube
- Risk: CNPG/Strimzi/Observability may starve app workloads.
- Mitigation: define strict requests/limits and right-size Minikube profile.

3. Operator upgrade regression
- Risk: CRD or operator changes break existing resources.
- Mitigation: separate upgrade PRs and validate in dev namespace first.

4. Secret decryption dependency
- Risk: Sealed Secrets controller unavailable.
- Mitigation: monitor controller health and keep recovery runbook.

5. Policy lockout
- Risk: overly strict policies block legitimate deploys.
- Mitigation: introduce policy in audit mode first, then enforce.

---

## 10. Definition of Done (Platform Track)

Platform implementation is complete when:
1. Root app and platform app tree are Synced/Healthy in Argo CD.
2. ingress-nginx, cnpg, strimzi, and observability are running.
3. Only dev overlays/resources are created; staging/prod remain deferred.
4. Platform CI validation and policy checks are mandatory and green.
5. Rollback and recovery runbooks are available and tested at least once in dev.

---

## 11. Suggested Execution Sequence (2-Week Sprint Model)

Sprint 1:
1. Phase A foundation
2. Phase B networking and secrets foundation
3. Partial Phase C (operators only)

Sprint 2:
1. Complete Phase C data platform resources
2. Phase D observability
3. Phase E policy and hardening
4. Runbook completion and done criteria verification

---

## 12. Immediate Next Actions

1. Create platform folder skeleton in GitOps repo exactly as in Section 2.
2. Implement Phase A files first (namespaces, projects, root app).
3. Add platform CI validation workflows before adding stateful operators.
4. Merge ingress as the first platform deployment slice.
5. Explicitly block staging/prod namespace resource creation in CI policy checks.
