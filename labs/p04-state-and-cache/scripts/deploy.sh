#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
ns="$(kubectl config view --minify -o jsonpath='{..namespace}')"
[[ "$ns" =~ ^student[0-9]{2}$ ]] || { echo "Unexpected namespace: $ns" >&2; exit 1; }
[[ "$(kubectl auth can-i create statefulsets -n "$ns")" == "yes" ]] || { echo "Missing StatefulSet permissions" >&2; exit 1; }
bash "$root/scripts/prepare-demo-password.sh"
kubectl apply -f "$root/manifests/01-orders-db.yaml"
kubectl apply -f "$root/manifests/02-orders-cache.yaml"
kubectl rollout status statefulset/orders-db --timeout=240s
kubectl rollout status deployment/orders-cache --timeout=180s
echo "[PASS] Postgres and Redis ready in $ns"
