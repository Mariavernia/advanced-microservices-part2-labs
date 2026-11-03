# P00 API contract

## Inventory

### `GET /api/inventory/{sku}`

Example:

```bash
curl http://localhost:8081/api/inventory/SKU-001
```

Example response:

```json
{
  "sku": "SKU-001",
  "available": 42,
  "reserved": 0,
  "servedBy": "inventory-6f8d7f8c9d-x7p2m",
  "serviceVersion": "0.1.0"
}
```

Known training SKUs:

- `SKU-001` — 42 units
- `SKU-002` — 7 units
- `SKU-003` — 0 units

## Orders

### `GET /api/orders/preview?sku={sku}&quantity={n}`

Example:

```bash
curl 'http://localhost:8080/api/orders/preview?sku=SKU-001&quantity=2'
```

Example response:

```json
{
  "sku": "SKU-001",
  "quantity": 2,
  "canBeFulfilled": true,
  "inventoryAvailable": 42,
  "servedBy": "orders-7cb98c8d45-w8k4q",
  "inventoryServedBy": "inventory-6f8d7f8c9d-x7p2m",
  "serviceVersion": "0.1.0"
}
```

## Health

Both services expose Spring Boot Actuator health endpoints under `/actuator/health`.
Probes are deliberately not configured in the P00 Kubernetes manifests; that gap becomes part of P02.
