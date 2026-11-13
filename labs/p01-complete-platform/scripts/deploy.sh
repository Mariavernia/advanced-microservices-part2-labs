#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="$(kubectl config view --minify -o jsonpath='{..namespace}')"
[[ "$NS" =~ ^(student[0-9]{2}|instructor)$ || "$NS" == "demo" ]] || { echo "Unexpected namespace: $NS" >&2; exit 1; }
[[ "$(kubectl auth can-i create deployments --namespace "$NS")" == "yes" ]] || { echo "Insufficient privileges in $NS" >&2; exit 1; }
echo "Applying P01 resources in namespace $NS"
kubectl apply -f "$ROOT/manifests/00-configmaps.yaml"
bash "$ROOT/scripts/prepare-demo-secret.sh"
for f in "$ROOT"/manifests/0[1-6]-*.yaml; do
  kubectl apply -f "$f"
done
echo "Deployment requested. Inspect: kubectl get deployment,pod,service"
