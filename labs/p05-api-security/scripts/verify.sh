#!/usr/bin/env bash
set -uo pipefail
# Verify only after individual experiments. Bearer tokens never enter argv.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0 fail=0
check(){
  local label="$1" expected="$2" profile="$3" path="$4" code
  code="$(python3 "$root/scripts/request.py" "$profile" "$path" --status-only)" || code=unreachable
  if [[ "$code" == "$expected" ]]; then
    printf '[PASS] %s\n' "$label"; ((pass+=1))
  else
    printf '[FAIL] %s (HTTP %s; expected %s)\n' "$label" "$code" "$expected"; ((fail+=1))
  fi
}
check 'Unauthenticated Orders is 401' 401 none '/api/orders/preview?sku=SKU-001&quantity=2'
check 'Public health is 200' 200 none '/actuator/health'
check 'Reader can preview orders' 200 reader '/api/orders/preview?sku=SKU-001&quantity=2'
check 'Reader cannot access admin payments' 403 reader '/api/payments/methods'
check 'Admin can access payments' 200 admin '/api/payments/methods'
printf '\nP05: PASS=%d FAIL=%d\n' "$pass" "$fail"
((fail==0))
