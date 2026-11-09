# Advanced Orders Platform

Reference application for the **Arquitectura de Microservicios Avanzada — Parte 2: Orquestación, Seguridad y Observabilidad** course.

This repository intentionally starts from a small synchronous baseline and evolves during the course. The goal is not to showcase every technology at once, but to make architectural forces observable before introducing the mechanism that addresses them.

## Start here

Students work from a **personal fork** and use **GitHub Codespaces** as the browser-based development workstation. Kubernetes workloads run in the course AKS cluster.

1. Create a Codespace from your fork.
2. Run `./scripts/login.sh`.
3. Run `./scripts/preflight.sh`.
4. Open [`labs/p00-kubernetes-survival-kit/README.md`](labs/p00-kubernetes-survival-kit/README.md).

Full setup instructions: [`docs/getting-started.md`](docs/getting-started.md).

## P00 baseline

```text
Client
  |
  v
Orders :8080
  |
  | HTTP — INVENTORY_BASE_URL
  v
Inventory :8080
```

The P00 baseline contains two independently deployable Spring Boot services:

- **orders** — exposes a read-only order preview operation and calls Inventory;
- **inventory** — exposes a small in-memory inventory catalogue.

The in-memory catalogue and the diagnostic `servedBy` fields are **training simplifications**, not production recommendations. Persistence is introduced later in the course when there is a concrete state-management problem to solve.

## Technology baseline

- Java 21
- Spring Boot 4.1.2
- Maven multi-module build
- Spring Boot Actuator
- OCI containers
- Kubernetes on Azure Kubernetes Service (AKS)
- GitHub Codespaces
- Azure CLI + `kubectl` + `kubelogin` + Helm

## Useful commands

```bash
make login
make preflight
make test
make package
make p00-verify
make p00-clean
```

The Codespace provides the required tooling, so students do not need to install course software locally.

## Local execution

Local Docker execution is optional and is not required for the course. If Docker is available:

```bash
docker compose up --build
```

Then:

```bash
curl 'http://localhost:8080/api/orders/preview?sku=SKU-001&quantity=2'
```

## Course structure

```text
.devcontainer/
config/
docs/
services/
  inventory/
  orders/
scripts/
labs/
  p00-kubernetes-survival-kit/
```

The platform will grow incrementally. Do not treat the P00 architecture as the target production architecture.

## P01 — Advanced Orders completa (en validación)

La práctica [P01](labs/p01-complete-platform/README.md) añade API Gateway, Payments,
Shipping y Notifications a Orders e Inventory. ConfigMap, Secret sintético,
requests/limits y diagnóstico de configuración se trabajan sobre seis workloads.

**Importante:** este curso utiliza el ACR real `advms26acr4366001b.azurecr.io`.
El equipo instructor debe publicar las seis imágenes `advancedorders/*:0.1.0`
mediante el script de administración del repositorio privado de infraestructura.
El PR de P01 debe superar CI y un ensayo end-to-end antes de publicarse a los alumnos.

No se procesan pagos, envíos ni notificaciones reales en este baseline.

## Prácticas posteriores preparadas en la rama de revisión

- [P02 — Resiliencia, probes y HPA](labs/p02-resilience/README.md).
- [P03 — Rolling, rollback y CI](labs/p03-rollouts-ci/README.md).
- [P04 — PostgreSQL, PVC y Redis](labs/p04-state-and-cache/README.md).

Estas prácticas incluyen manifiestos o procedimientos ejecutables, pero no están aún validadas desde un Codespace de alumno contra el AKS real. P04 ilustra estado y caché con SQL/Redis, sin afirmar que Orders Java ya persista datos. La liberación a alumnos requiere el ensayo completo y la revisión del instructor.

## P05 — API security (staged)

The [P05 security lab](labs/p05-api-security/README.md) introduces a separate
JWT-protected API Gateway image. P00–P04 continue to use the existing `0.1.0`
baseline image. P05 is **not executable** until the instructor provisions a
shared HTTPS Keycloak OIDC issuer, client/roles and the new `0.2.0-sec` gateway
image. Do not place passwords, tokens or Keycloak admin credentials in Git.
