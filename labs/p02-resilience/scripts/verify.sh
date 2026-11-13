#!/usr/bin/env bash
set -uo pipefail
pass=0
fail=0
ok(){ printf '[PASS] %s\n' "$1"; pass=$((pass+1)); }
bad(){ printf '[FAIL] %s\n' "$1"; fail=$((fail+1)); }
ns="$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)"
[[ "$ns" =~ ^(student[0-9]{2}|instructor)$ ]] || { echo "Expected studentNN namespace; got: $ns" >&2; exit 2; }
if kubectl rollout status deployment/orders --timeout=120s >/dev/null 2>&1; then ok 'orders Deployment rollout ready'; else bad 'orders rollout not ready'; fi
for probe in readinessProbe livenessProbe startupProbe; do
  value="$(kubectl get deployment orders -o jsonpath="{.spec.template.spec.containers[0].$probe.httpGet.path}" 2>/dev/null || true)"
  case "$probe" in
    startupProbe) expected=/actuator/health ;;
    readinessProbe) expected=/actuator/health/readiness ;;
    livenessProbe) expected=/actuator/health/liveness ;;
  esac
  [[ "$value" == "$expected" ]] && ok "$probe: $value" || bad "$probe expected $expected ($value)"
done
cpu="$(kubectl get deployment orders -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null || true)"
[[ "$cpu" == 100m ]] && ok 'Orders CPU request is 100m' || bad "Orders CPU request expected 100m ($cpu)"
kubectl get hpa orders >/dev/null 2>&1 && ok 'orders HPA configured' || bad 'orders HPA missing'
max="$(kubectl get hpa orders -o jsonpath='{.spec.maxReplicas}' 2>/dev/null || true)"
[[ "$max" == 3 ]] && ok 'HPA maximum is 3' || bad "HPA max not 3 ($max)"

if kubectl get hpa orders -o json 2>/dev/null | jq -e '
  .spec.minReplicas == 1 and .spec.maxReplicas == 3 and
  .spec.scaleTargetRef.kind == "Deployment" and .spec.scaleTargetRef.name == "orders" and
  any(.spec.metrics[]?; .type == "Resource" and .resource.name == "cpu" and
      .resource.target.type == "Utilization" and .resource.target.averageUtilization == 60) and
  .spec.behavior.scaleDown.stabilizationWindowSeconds == 120
' >/dev/null 2>&1; then ok 'HPA CPU target, bounds and stabilization correct'
else bad 'HPA expected CPU 60%, min=1, max=3, stabilization=120s'
fi

# A configured HPA can be inactive when Metrics Server is missing.
# Allow time for the first metrics sample and HPA reconciliation loop.
metrics_ready=false
for attempt in $(seq 1 12); do
  hpa_json="$(kubectl get hpa orders -o json 2>/dev/null || true)"
  if printf '%s' "$hpa_json" | jq -e '
    any(.status.currentMetrics[]?;
      .type == "Resource" and .resource.name == "cpu"
      and (.resource.current.averageUtilization | type == "number"))
  ' >/dev/null 2>&1; then
    metrics_ready=true
    break
  fi
  if (( attempt < 12 )); then sleep 5; fi
done
if [[ "$metrics_ready" == "true" ]]; then
  current="$(printf '%s' "$hpa_json" | jq -r '.status.currentMetrics[] | select(.type=="Resource" and .resource.name=="cpu") | .resource.current.averageUtilization | select(type=="number")' | head -n 1)"
  ok "HPA receiving CPU utilization metrics: ${current}% of CPU request"
else
  bad 'HPA has no CPU utilization metric after retries (configured is not active)'
  echo '  Check: kubectl describe hpa orders'
  echo '         kubectl top pods -l app.kubernetes.io/name=orders'
  echo '  Instructor: kubectl get apiservice v1beta1.metrics.k8s.io'
fi

printf 'P02: PASS=%s FAIL=%s\n' "$pass" "$fail"
(( fail == 0 ))
