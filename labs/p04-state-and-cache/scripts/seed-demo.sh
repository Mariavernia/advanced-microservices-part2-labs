#!/usr/bin/env bash
set -euo pipefail
ns="$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)"
[[ "$ns" =~ ^student[0-9]{2}$ ]] || { echo "Unexpected namespace: $ns" >&2; exit 2; }
kubectl get pod orders-db-0 >/dev/null || { echo "PostgreSQL is not deployed" >&2; exit 1; }
kubectl get deployment orders-cache >/dev/null || { echo "Redis is not deployed" >&2; exit 1; }
kubectl exec orders-db-0 -- sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U orders -d ordersdb -v ON_ERROR_STOP=1 -c "CREATE TABLE IF NOT EXISTS course_order_drafts (order_id text PRIMARY KEY, sku text NOT NULL, quantity integer NOT NULL, status text NOT NULL);"'
kubectl exec orders-db-0 -- sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U orders -d ordersdb -v ON_ERROR_STOP=1 -c "INSERT INTO course_order_drafts (order_id,sku,quantity,status) VALUES ('\''ORD-DEMO-001'\'','\''SKU-001'\'',2,'\''CREATED'\'') ON CONFLICT (order_id) DO UPDATE SET sku=EXCLUDED.sku,quantity=EXCLUDED.quantity,status=EXCLUDED.status;"'
kubectl exec deployment/orders-cache -- redis-cli SET order:ORD-DEMO-001 '{"orderId":"ORD-DEMO-001","sku":"SKU-001","quantity":2,"status":"CREATED"}'
echo "[PASS] PostgreSQL has order ORD-DEMO-001 status CREATED; Redis has a CREATED snapshot."
echo "Next: run the SQL query and observe the cache; do not display the PostgreSQL password."
