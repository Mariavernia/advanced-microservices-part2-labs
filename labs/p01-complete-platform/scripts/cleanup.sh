#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="$(kubectl config view --minify -o jsonpath='{..namespace}')"
[[ "$NS" =~ ^(student[0-9]{2}|instructor)$ || "$NS" == "demo" ]] || { echo "Unexpected namespace: $NS" >&2; exit 1; }
echo "Removing P01 application from namespace $NS (including Orders and Inventory shared with P00)."
for f in "$ROOT"/manifests/0[1-6]-*.yaml; do
  kubectl delete -f "$f" --ignore-not-found
done
kubectl delete -f "$ROOT/manifests/00-configmaps.yaml" --ignore-not-found
kubectl delete secret notifications-provider --ignore-not-found
echo "Only application-scoped objects were removed; namespace and platform were untouched."
