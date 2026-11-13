#!/usr/bin/env bash
set -uo pipefail
PASS=0
FAIL=0
ok(){ printf '[PASS] %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
NS="$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)"
[[ "$NS" =~ ^(student[0-9]{2}|instructor)$ || "$NS" == "demo" ]] || { no "Unrecognized namespace: $NS"; exit 1; }
echo "P01 verification in namespace $NS"
for svc in inventory orders payments shipping notifications api-gateway; do
  if kubectl get deployment "$svc" >/dev/null 2>&1; then
    ready="$(kubectl get deployment "$svc" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
    [[ "$ready" =~ ^[1-9][0-9]*$ ]] && ok "$svc Ready" || no "$svc not Ready"
  else no "$svc Deployment absent"; fi
  kubectl get service "$svc" >/dev/null 2>&1 && ok "$svc Service present" || no "$svc Service absent"
done
check_route(){
  local label="$1" path="$2" expression="$3" output status body attempt detail
  detail="No response yet"
  # P01 does not yet define HTTP readiness probes. Retry the initial request,
  # but preserve the final error instead of swallowing curl stderr/HTTP bodies.
  for attempt in 1 2 3 4 5; do
    if output="$(kubectl exec deploy/api-gateway -- \
      curl -sS --connect-timeout 5 --max-time 15 \
      -w '\n%{http_code}' "http://localhost:8080$path" 2>&1)"; then
      status="$(printf '%s\n' "$output" | tail -n 1)"
      body="$(printf '%s\n' "$output" | sed '$d')"
      if [[ "$status" =~ ^2[0-9][0-9]$ ]]; then
        if printf '%s' "$body" | jq -e "$expression" >/dev/null 2>&1; then
          ok "$label (HTTP $status)"
          return
        fi
        no "$label: HTTP $status but JSON did not match expected assertion"
        printf '  Response: %.1200s\n' "$body"
        return
      fi
      detail="HTTP $status; body: $body"
    else
      detail="curl/kubectl error: $output"
    fi
    if (( attempt < 5 )); then sleep 3; fi
  done
  no "$label: still failing after 5 attempts"
  printf '  Last diagnostic: %.1200s\n' "$detail"
  echo '  Next: kubectl logs deployment/orders --tail=80'
  echo '        kubectl exec deployment/api-gateway -- curl -siS http://orders:8080/actuator/health'
}
if kubectl get pod -l app.kubernetes.io/name=api-gateway >/dev/null 2>&1; then
  check_route "Gateway → Orders → Inventory" '/api/orders/preview?sku=SKU-001&quantity=2' '.canBeFulfilled == true'
  check_route "Gateway → Payments" '/api/payments/methods' '.chargingEnabled == false'
  check_route "Gateway → Shipping" '/api/shipping/quote?destination=ES&weightGrams=500' '.priceCents == 499'
  check_route "Gateway → Notifications" '/api/notifications/provider' '.credentialConfigured == true and .deliveryEnabled == false'
else no "Gateway Pod not found"; fi
printf '\nP01: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL==0 ))
