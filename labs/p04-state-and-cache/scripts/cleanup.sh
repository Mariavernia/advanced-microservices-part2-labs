#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ns="$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)"
[[ "$ns" =~ ^(student[0-9]{2}|instructor)$ ]] || { echo "Unexpected namespace $ns" >&2; exit 2; }
if [[ "${1:-}" == "--help" ]]; then
  echo "Usage: bash labs/p04-state-and-cache/scripts/cleanup.sh [--destroy-data]"
  echo "Without --destroy-data, leaves the synthetic password Secret and PVC in place."
  echo "--destroy-data permanently deletes the PostgreSQL PVC and demo credentials."
  exit 0
fi
if [[ -n "${1:-}" && "${1:-}" != "--destroy-data" ]]; then echo "Invalid option" >&2; exit 2; fi
if [[ "${1:-}" == "--destroy-data" ]]; then
  echo "This permanently removes the P04 workload, PVC and demo credentials from namespace $ns."
  read -r -p 'Type DESTROY to continue: ' response
  [[ "$response" == "DESTROY" ]] || { echo "Nothing deleted. Existing workloads, PVC and Secret are preserved."; exit 0; }
fi
kubectl delete -f "$root/manifests/02-orders-cache.yaml" --ignore-not-found
kubectl delete -f "$root/manifests/01-orders-db.yaml" --ignore-not-found --wait=true
if [[ "${1:-}" == "--destroy-data" ]]; then
  kubectl delete pvc dbdata-orders-db-0 --ignore-not-found
  kubectl delete secret orders-postgres-auth --ignore-not-found
  echo "[PASS] P04 workload and associated demo data removed."
else
  echo "[PASS] Workloads removed. PVC and synthetic password remain for recovery."
fi
