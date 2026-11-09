#!/usr/bin/env bash
set -uo pipefail
PASS=0
FAIL=0
ok(){ printf '[PASS] %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
NS="$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)"
[[ "$NS" =~ ^student[0-9]{2}$ || "$NS" == "demo" ]] || { no "Unrecognized namespace: $NS"; exit 1; }
echo "P01 verification in namespace $NS"
for svc in inventory orders payments shipping notifications api-gateway; do
  if kubectl get deployment "$svc" >/dev/null 2>&1; then
    ready="$(kubectl get deployment "$svc" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
    [[ "$ready" =~ ^[1-9][0-9]*$ ]] && ok "$svc Ready" || no "$svc not Ready"
  else no "$svc Deployment absent"; fi
  kubectl get service "$svc" >/dev/null 2>&1 && ok "$svc Service present" || no "$svc Service absent"
done
check_route(){
  local label="$1" path="$2" expression="$3" output
  output="$(kubectl exec deploy/api-gateway -- curl -fsS --max-time 10 "http://localhost:8080$path" 2>/dev/null)" || { no "$label: HTTP request failed"; return; }
  printf '%s' "$output" | jq -e "$expression" >/dev/null 2>&1 && ok "$label" || no "$label: unexpected JSON"
}
if kubectl get pod -l app.kubernetes.io/name=api-gateway >/dev/null 2>&1; then
  check_route "Gateway → Orders → Inventory" '/api/orders/preview?sku=SKU-001&quantity=2' '.canBeFulfilled == true'
  check_route "Gateway → Payments" '/api/payments/methods' '.chargingEnabled == false'
  check_route "Gateway → Shipping" '/api/shipping/quote?destination=ES&weightGrams=500' '.priceCents == 499'
  check_route "Gateway → Notifications" '/api/notifications/provider' '.credentialConfigured == true and .deliveryEnabled == false'
else no "Gateway Pod not found"; fi
printf '\nP01: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL==0 ))
