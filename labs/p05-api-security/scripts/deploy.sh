#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck disable=SC1090
source "$root/config/course.env"
ns="$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)"
[[ "$ns" =~ ^(student[0-9]{2}|instructor)$ || "$ns" == "demo" ]] || { echo "Unexpected namespace: $ns" >&2; exit 2; }
issuer="${OIDC_ISSUER_URI:-}"
audience="${OIDC_AUDIENCE:-advanced-orders-api}"
[[ "$issuer" == https://* ]] || { echo "OIDC_ISSUER_URI must be the instructor-provided HTTPS issuer URL (not configured)." >&2; exit 2; }
[[ "$(kubectl auth can-i patch deployments.apps -n "$ns")" == "yes" ]] || { echo "Insufficient deployment permissions in $ns" >&2; exit 1; }
[[ -n "$audience" ]] || { echo "Missing OIDC_AUDIENCE" >&2; exit 2; }
for bin in jq curl; do command -v "$bin" >/dev/null || { echo "Missing $bin" >&2; exit 1; }; done
metadata="$(curl --fail --silent --show-error --max-time 15 "${issuer%/}/.well-known/openid-configuration")" || {
  echo "Issuer metadata unreachable; contact the instructor." >&2; exit 1;
}
remote_issuer="$(jq -r '.issuer // empty' <<<"$metadata")"
[[ "$remote_issuer" == "$issuer" ]] || { echo "OIDC issuer mismatch: expected '$issuer', received '$remote_issuer'" >&2; exit 1; }
kubectl get service api-gateway >/dev/null || { echo "First deploy and verify P01." >&2; exit 1; }
kubectl create configmap p05-security-settings \
  --from-literal="OIDC_ISSUER_URI=$issuer" \
  --from-literal="OIDC_AUDIENCE=$audience" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$root/labs/p05-api-security/manifests/01-api-gateway-secure.yaml"
kubectl rollout status deployment/api-gateway --timeout=240s
echo "[PASS] P05 protected Gateway deployed in $ns."
echo "Verify the token flow using the private per-user cache, not the repository."
