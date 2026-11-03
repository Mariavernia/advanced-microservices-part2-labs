# ADR-001 — Start with synchronous HTTP between Orders and Inventory

- **Status:** Accepted for baseline
- **Date:** 2026-11-03

## Context

The course needs a system whose behaviour can be observed before advanced resilience and distributed-communication patterns are introduced.

If the baseline already contained Kafka, retries, circuit breakers, service mesh traffic policy and persistence, students would see mechanisms without first observing the problems that motivate them.

## Decision

The baseline uses one synchronous HTTP dependency:

```text
Orders → Inventory
```

Orders receives `INVENTORY_BASE_URL` through external configuration.

## Consequences

### Positive

- dependency and failure propagation are easy to observe;
- Kubernetes service discovery is visible in P00;
- later timeout, retry, circuit breaker and event-driven changes have a clear before/after comparison;
- the application remains readable for students who are not Spring specialists.

### Negative / deliberately accepted

- Orders is temporarily coupled to Inventory availability and latency;
- the baseline has no application-level resilience;
- the baseline is not the final production architecture.

## Training note

The absence of resilience patterns is intentional. It must not be presented as a production recommendation.
