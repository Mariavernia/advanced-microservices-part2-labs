#!/usr/bin/env bash
set -uo pipefail
# This verifier intentionally does not print JWTs or token-bearing command lines.
BASE_URL="${BASE_URL:-http://127.0.0.1:8080}"
reader_file="$HOME/.cache/advanced-orders/reader.jwt"
admin_file="$HOME/.cache/advanced-orders/admin.jwt"
pass=0 fail=0
ok(){ printf '[PASS] %s\n' "$1"; ((pass+=1)); }
bad(){ printf '[FAIL] %s (HTTP %s)\n' "$1" "$2"; ((fail+=1)); }
check(){
  local label="$1" expected="$2" path="$3" token_file="${4:-}" code
  if [[ -n "$token_file" ]]; then
    [[ -s "$token_file" ]] || { bad "$label (missing token file)" 'none'; return; }
    local token
    token="$(cat "$token_file")"
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
      -H "Authorization: Bearer $token" "$BASE_URL$path" 2>/dev/null || true)"
    unset token
  else
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$BASE_URL$path" 2>/dev/null || true)"
  fi
  [[ "$code" == "$expected" ]] && ok "$label" || bad "$label (expected $expected)" "${code:-unreachable}"
}
check 'Unauthenticated Orders is 401' 401 '/api/orders/preview?sku=SKU-001&quantity=2'
check 'Public health is 200' 200 '/actuator/health'
check 'Reader can preview orders' 200 '/api/orders/preview?sku=SKU-001&quantity=2' "$reader_file"
check 'Reader cannot access admin payments' 403 '/api/payments/methods' "$reader_file"
check 'Admin can access payments' 200 '/api/payments/methods' "$admin_file"
printf '\nP05: PASS=%d FAIL=%d\n' "$pass" "$fail"
(( fail == 0 ))
