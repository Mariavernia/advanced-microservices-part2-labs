#!/usr/bin/env bash
set -u

PASS=0
FAIL=0

pass() {
  printf '[PASS] %s\n' "$1"
  PASS=$((PASS + 1))
}

fail() {
  printf '[FAIL] %s\n' "$1"
  FAIL=$((FAIL + 1))
}

exists() {
  kubectl get "$1" "$2" >/dev/null 2>&1
}

ready_replicas() {
  kubectl get deployment "$1" -o jsonpath='{.status.readyReplicas}' 2>/dev/null
}

echo 'Advanced Orders Platform — P00 verification'
echo

CURRENT_NS=$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null || true)
if [[ -n "${CURRENT_NS}" && "${CURRENT_NS}" != "default" ]]; then
  pass "Kubernetes context uses namespace ${CURRENT_NS}"
else
  fail "Kubernetes context does not have a non-default namespace"
fi

for resource in 'deployment inventory' 'deployment orders' 'service inventory' 'service orders'; do
  read -r kind name <<<"$resource"
  if exists "$kind" "$name"; then
    pass "$kind/$name exists"
  else
    fail "$kind/$name exists"
  fi
done

for deployment in inventory orders; do
  READY=$(ready_replicas "$deployment" || true)
  if [[ "${READY:-0}" -ge 1 ]]; then
    pass "$deployment has at least one Ready replica"
  else
    fail "$deployment has at least one Ready replica"
  fi
done

ENDPOINT_COUNT=$(kubectl get endpointslice \
  -l kubernetes.io/service-name=inventory \
  -o json 2>/dev/null | jq '[.items[].endpoints[]?.addresses[]?] | length' 2>/dev/null || echo 0)

if [[ "${ENDPOINT_COUNT:-0}" -ge 1 ]]; then
  pass "Inventory Service has ${ENDPOINT_COUNT} endpoint address(es)"
else
  fail "Inventory Service has endpoint addresses"
fi

ORDERS_POD=$(kubectl get pod \
  -l app.kubernetes.io/name=orders \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

# Capture stderr: a failed command must be diagnosable as DNS, TCP,
# missing curl, HTTP response code or an unavailable Kubernetes exec.
# The test is read-only. Transient post-start failures are retried.
echo 'Checking Inventory health over Kubernetes Service DNS from Orders...'
if [[ -z "$ORDERS_POD" ]]; then
  fail "Orders Pod not found for network test"
else
  NETWORK_OUTPUT=""
  NETWORK_OK=false
  for attempt in 1 2 3; do
    if NETWORK_OUTPUT="$(kubectl exec "$ORDERS_POD" -- \
      curl -fsS --connect-timeout 3 --max-time 8 \
      http://inventory:8080/actuator/health 2>&1)"; then
      NETWORK_OK=true
      break
    fi
    sleep 2
  done
  if [[ "$NETWORK_OK" == "true" ]]; then
    pass "Orders Pod can reach Inventory by Service DNS ($NETWORK_OUTPUT)"
  else
    fail "Orders Pod can reach Inventory by Service DNS"
    printf '  Last curl/exec output: %s\n' "${NETWORK_OUTPUT:-<empty>}"
    echo '  Try: kubectl exec deployment/orders -- curl -v --max-time 10 http://inventory:8080/actuator/health'
    echo '       kubectl get endpointslice -l kubernetes.io/service-name=inventory'
    echo '       kubectl logs deployment/inventory --tail=50'
  fi
fi

echo
echo "Result: ${PASS} PASS / ${FAIL} FAIL"

if [[ "$FAIL" -ne 0 ]]; then
  echo "P00 is not complete yet. Use Kubernetes evidence to investigate the failed checks."
  exit 1
fi

echo "P00 completed successfully. Be ready to explain why each check passes."
