#!/usr/bin/env bash
set -euo pipefail
ns="$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)"
[[ "$ns" =~ ^student[0-9]{2}$ ]] || { echo "Unexpected namespace $ns" >&2; exit 1; }
kubectl get statefulset orders-db >/dev/null
kubectl get deployment orders-cache >/dev/null
kubectl get pvc dbdata-orders-db-0 >/dev/null
kubectl exec orders-db-0 -- sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_isready -U orders -d ordersdb' >/dev/null
kubectl exec deployment/orders-cache -- redis-cli ping | grep -qx PONG
echo "[PASS] P04: StatefulSet, PVC, PostgreSQL, Redis available."
