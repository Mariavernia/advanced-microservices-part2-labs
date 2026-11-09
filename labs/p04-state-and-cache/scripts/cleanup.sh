#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ns="$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)"
[[ "$ns" =~ ^student[0-9]{2}$ ]] || { echo "Unexpected namespace $ns" >&2; exit 2; }
if [[ "${1:-}" == "--help" ]]; then
  echo "Usage: bash labs/p04-state-and-cache/scripts/cleanup.sh [--destroy-data]"
  echo "Without --destroy-data, leaves the synthetic password Secret and PVC in place."
  echo "--destroy-data permanently deletes the PostgreSQL PVC and demo credentials."
  exit 0
fi
if [[ -n "${1:-}" && "${1:-}" != "--destroy-data" ]]; then echo "Invalid option" >&2; exit 2; fi
kubectl delete -f "$root/manifests/02-orders-cache.yaml" --ignore-not-found
kubectl delete -f "$root/manifests/01-orders-db.yaml" --ignore-not-found --wait=true
if [[ "${1:-}" == "--destroy-data" ]]; then
  echo "This permanently deletes P04 database data from namespace $ns."
  read -r -p 'Type DESTROY to continue: ' response
  [[ "$response" == "DESTROY" ]] || { echo "Preserved PVC and Secret."; exit 0; }
  kubectl delete pvc dbdata-orders-db-0 --ignore-not-found
  kubectl delete secret orders-postgres-auth --ignore-not-found
else
  echo "[PASS] Workloads removed. PVC and synthetic password remain for recovery."
fi
