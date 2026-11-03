# Architecture overview — baseline 0.1

## Context

Advanced Orders Platform is a reference system used to make distributed-system and platform behaviour observable during the course.

The platform begins deliberately small:

```text
                 +------------------+
                 |      Client      |
                 +---------+--------+
                           |
                           | HTTP
                           v
                 +---------+--------+
                 |      Orders      |
                 |      :8080       |
                 +---------+--------+
                           |
                           | HTTP
                           | inventory:8080
                           v
                 +---------+--------+
                 |    Inventory     |
                 |      :8080       |
                 +------------------+
```

## Responsibilities

### Orders

For P00, Orders exposes a preview operation. It validates the requested quantity, queries Inventory synchronously, and reports whether the requested quantity can be fulfilled.

It does **not** persist an order yet. That omission is intentional: persistence and distributed state are introduced only when the learning scenario needs them.

### Inventory

Inventory owns the availability view for a small catalogue. In P00 the catalogue is held in memory so Pod replacement can be studied without adding database concepts prematurely.

## Configuration

Orders does not know a Pod IP. It receives the Inventory base URL through external configuration:

```text
INVENTORY_BASE_URL=http://inventory:8080
```

In Kubernetes, `inventory` is the Service DNS name in the student's namespace.

## Diagnostic fields

Responses expose:

- `servedBy`
- `serviceVersion`

Orders also exposes `inventoryServedBy` in preview responses.

These fields are intentionally included for training so students can observe which replica handled a request. They would not normally be part of a public business API.

## Evolution path

Later practices add or change:

- configuration and secrets;
- health probes and resources;
- CI/CD and versioned images;
- PostgreSQL and Redis;
- identity and authorization;
- service mesh and traffic management;
- telemetry and incident investigation;
- asynchronous messaging and distributed-data patterns in Part 1.
