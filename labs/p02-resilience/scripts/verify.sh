#!/usr/bin/env bash
set -uo pipefail
pass=0
fail=0
ok(){ printf '[PASS] %s\n' "$1"; pass=$((pass+1)); }
bad(){ printf '[FAIL] %s\n' "$1"; fail=$((fail+1)); }
ns="$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)"
[[ "$ns" =~ ^student[0-9]{2}$ ]] || { echo "Expected studentNN namespace; got: $ns" >&2; exit 2; }
if kubectl rollout status deployment/orders --timeout=120s >/dev/null 2>&1; then ok 'orders Deployment rollout ready'; else bad 'orders rollout not ready'; fi
for probe in readinessProbe livenessProbe startupProbe; do
  value="$(kubectl get deployment orders -o jsonpath="{.spec.template.spec.containers[0].$probe.httpGet.path}" 2>/dev/null || true)"
  [[ "$value" == /actuator/health* ]] && ok "$probe: $value" || bad "$probe missing or unexpected ($value)"
done
kubectl get hpa orders >/dev/null 2>&1 && ok 'orders HPA configured' || bad 'orders HPA missing'
max="$(kubectl get hpa orders -o jsonpath='{.spec.maxReplicas}' 2>/dev/null || true)"
[[ "$max" == 3 ]] && ok 'HPA maximum is 3' || bad "HPA max not 3 ($max)"
printf 'P02: PASS=%s FAIL=%s\n' "$pass" "$fail"
(( fail == 0 ))
