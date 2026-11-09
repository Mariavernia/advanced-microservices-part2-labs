#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ns="$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)"
[[ "$ns" =~ ^student[0-9]{2}$ || "$ns" == "demo" ]] || { echo "Unexpected namespace $ns" >&2; exit 2; }
echo "Restoring P01's non-secure Gateway image only inside $ns..."
kubectl apply -f "$root/labs/p01-complete-platform/manifests/06-api-gateway.yaml"
# The P05 security profile must not persist on the P01 application.
kubectl set env deployment/api-gateway SPRING_PROFILES_ACTIVE- >/dev/null 2>&1 || true
kubectl rollout status deployment/api-gateway --timeout=240s
kubectl delete configmap p05-security-settings --ignore-not-found
echo "[PASS] P01 Gateway restored."
echo "Local tokens are not removed automatically: rm -f ~/.cache/advanced-orders/{reader,admin}.jwt"
