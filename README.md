# Advanced Orders Platform

Reference application for the **Arquitectura de Microservicios Avanzada** courses.

This repository intentionally starts from a small synchronous baseline and evolves during the course. The goal is not to showcase every technology at once, but to make architectural forces observable before introducing the mechanism that addresses them.

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
- Kubernetes manifests for P00

## Build

```bash
mvn test
mvn package
```

The official course Codespace provides Java and Maven, so no local installation is required during the course.

## Local execution

If Docker is available:

```bash
docker compose up --build
```

Then:

```bash
curl 'http://localhost:8080/api/orders/preview?sku=SKU-001&quantity=2'
```

## Course structure

```text
docs/
services/
  inventory/
  orders/
labs/
  p00-kubernetes-survival-kit/
```

The platform will grow incrementally. Do not treat the P00 architecture as the target production architecture.
