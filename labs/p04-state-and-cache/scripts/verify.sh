#!/usr/bin/env bash
set -uo pipefail
pass=0; fail=0
ok(){ printf '[PASS] %s\n' "$1"; pass=$((pass+1)); }
bad(){ printf '[FAIL] %s\n' "$1"; fail=$((fail+1)); }
ns="$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)"
[[ "$ns" =~ ^(student[0-9]{2}|instructor)$ ]] || { echo "Unexpected namespace $ns" >&2; exit 2; }
kubectl get statefulset orders-db >/dev/null 2>&1 && ok "PostgreSQL StatefulSet exists" || bad "PostgreSQL StatefulSet missing"
kubectl get deployment orders-cache >/dev/null 2>&1 && ok "Redis Deployment exists" || bad "Redis Deployment missing"
kubectl get pvc dbdata-orders-db-0 >/dev/null 2>&1 && ok "PVC retained" || bad "PostgreSQL PVC missing"
if kubectl exec orders-db-0 -- sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_isready -U orders -d ordersdb' >/dev/null 2>&1; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL not ready"; fi
if kubectl exec deployment/orders-cache -- redis-cli ping 2>/dev/null | grep -qx PONG; then ok "Redis answers PONG"; else bad "Redis not ready"; fi
state="$(kubectl exec orders-db-0 -- sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U orders -d ordersdb -At -c "SELECT status FROM course_order_drafts WHERE order_id = '\''ORD-DEMO-001'\'';"' 2>/dev/null | tr -d '\r\n' || true)"
[[ "$state" == "CONFIRMED" ]] && ok "Persisted order status CONFIRMED" || bad "Expected persisted CONFIRMED; observed ${state:-none}"
printf '\nP04: PASS=%d FAIL=%d\n' "$pass" "$fail"
((fail==0))
