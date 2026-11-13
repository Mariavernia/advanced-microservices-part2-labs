#!/usr/bin/env bash
set -uo pipefail
pass=0; fail=0
ok(){ printf '[PASS] %s\n' "$1"; pass=$((pass+1)); }
bad(){ printf '[FAIL] %s\n' "$1"; fail=$((fail+1)); }
extended=false
initial=0
if (( $# != 0 )); then
  if [[ "$#" -eq 2 && "$1" == "--extended" && "$2" =~ ^[1-5]$ ]]; then
    extended=true
    initial="$2"
  else
    echo "Usage: $0 [--extended INITIAL_QUANTITY (1..5)]" >&2
    exit 2
  fi
fi
ns="$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)"
[[ "$ns" =~ ^(student[0-9]{2}|instructor)$ ]] || { echo "Unexpected namespace $ns" >&2; exit 2; }
kubectl get statefulset orders-db >/dev/null 2>&1 && ok "PostgreSQL StatefulSet exists" || bad "PostgreSQL StatefulSet missing"
kubectl get deployment orders-cache >/dev/null 2>&1 && ok "Redis Deployment exists" || bad "Redis Deployment missing"
kubectl get pvc dbdata-orders-db-0 >/dev/null 2>&1 && ok "PVC retained" || bad "PostgreSQL PVC missing"
if kubectl exec orders-db-0 -- sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_isready -U orders -d ordersdb' >/dev/null 2>&1; then ok "PostgreSQL accepts connections"; else bad "PostgreSQL not ready"; fi
if kubectl exec deployment/orders-cache -- redis-cli ping 2>/dev/null | grep -qx PONG; then ok "Redis answers PONG"; else bad "Redis not ready"; fi
state="$(kubectl exec orders-db-0 -- sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U orders -d ordersdb -At -c "SELECT status FROM course_order_drafts WHERE order_id = '\''ORD-DEMO-001'\'';"' 2>/dev/null | tr -d '\r\n' || true)"
[[ "$state" == "CONFIRMED" ]] && ok "Persisted order status CONFIRMED" || bad "Expected persisted CONFIRMED; observed ${state:-none}"
if [[ "$extended" == true ]]; then
  expected_qty=$((initial + 3))
  row="$(kubectl exec -i orders-db-0 -- sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -X -U orders -d ordersdb -v ON_ERROR_STOP=1 -At' <<'SQL'
SELECT json_build_object('orderId',order_id,'sku',sku,'quantity',quantity,'status',status,'version',version)
FROM course_order_drafts WHERE order_id='ORD-DEMO-002';
SQL
  )" || row=""
  if jq -e --argjson qty "$expected_qty" '.orderId == "ORD-DEMO-002" and .sku == "SKU-001" and .quantity == $qty and .status == "CREATED" and .version == 4' <<< "$row" >/dev/null 2>&1; then
    ok "Extended order has expected quantity and version 4"
  else
    bad "Extended order missing or unexpected state (expected quantity=$expected_qty, version=4)"
  fi
  cache="$(kubectl exec deployment/orders-cache -- redis-cli --raw GET order:ORD-DEMO-002 2>/dev/null)" || cache=""
  if [[ -n "$row" && -n "$cache" ]] && jq -en --argjson db "$row" --argjson cached "$cache" '$db == $cached' >/dev/null 2>&1; then
    ok "Extended Redis snapshot matches PostgreSQL"
  else
    bad "Extended Redis snapshot missing, expired or inconsistent"
  fi
fi
printf '\nP04: PASS=%d FAIL=%d\n' "$pass" "$fail"
((fail==0))
