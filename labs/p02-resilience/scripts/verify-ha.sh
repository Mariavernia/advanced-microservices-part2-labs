#!/usr/bin/env bash
set -uo pipefail

PASS=0; FAIL=0
ok() { printf '[PASS] %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
ns="$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)"
if [[ ! "$ns" =~ ^(student[0-9]{2}|instructor)$ && "$ns" != "demo" ]]; then
  bad "Unexpected namespace: ${ns:-none}"
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then bad "jq unavailable"; exit 2; fi
pods="$(kubectl get pods -l app.kubernetes.io/name=orders -o json 2>/dev/null || true)"
if [[ -z "$pods" ]]; then bad "Cannot read Orders pods"; exit 1; fi
ready="$(jq '[.items[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' <<< "$pods" 2>/dev/null || echo 0)"
nodes="$(jq -r '[.items[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True")) | .spec.nodeName // empty] | unique | length' <<< "$pods" 2>/dev/null || echo 0)"
[[ "$ready" -ge 2 ]] && ok "At least two Ready Orders pods" || bad "Ready Orders pods: $ready (expected >=2)"
[[ "$nodes" -ge 2 ]] && ok "Ready Orders pods on two distinct nodes" || bad "Distinct nodes: $nodes (expected >=2)"
hpaMin="$(kubectl get hpa orders -o jsonpath='{.spec.minReplicas}' 2>/dev/null || true)"
[[ "$hpaMin" == "2" ]] && ok "HPA minimum replicas is 2" || bad "HPA minReplicas: ${hpaMin:-missing}"
pdbMin="$(kubectl get pdb orders-ha-demo -o jsonpath='{.spec.minAvailable}' 2>/dev/null || true)"
[[ "$pdbMin" == "1" ]] && ok "PDB minAvailable is 1" || bad "PDB minAvailable: ${pdbMin:-missing}"
spread="$(kubectl get deploy orders -o json 2>/dev/null | jq -r '[.spec.template.spec.topologySpreadConstraints[]? | select(.topologyKey=="kubernetes.io/hostname" and .whenUnsatisfiable=="DoNotSchedule" and .minDomains==2)] | length' 2>/dev/null || echo 0)"
[[ "$spread" -gt 0 ]] && ok "Topology spread requires two eligible hostname domains" || bad "Missing two-domain topology spread rule"
endpoints="$(kubectl get endpointslice -l kubernetes.io/service-name=orders -o json 2>/dev/null | jq '[.items[].endpoints[]? | select(.conditions.ready==true)] | length' 2>/dev/null || echo 0)"
[[ "$endpoints" -ge 2 ]] && ok "At least two Ready Service endpoints" || bad "Ready Service endpoints: $endpoints (expected >=2)"
printf '\nP02-H: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
((FAIL==0))
