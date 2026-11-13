#!/usr/bin/env bash
set -euo pipefail
ns="$(kubectl config view --minify -o jsonpath='{..namespace}')"
[[ "$ns" =~ ^(student[0-9]{2}|instructor)$ ]] || { echo "Unexpected namespace $ns" >&2; exit 1; }
if kubectl get secret orders-postgres-auth >/dev/null 2>&1; then
  echo "[PASS] Existing synthetic Postgres password reused in $ns."
else
  password="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
  kubectl create secret generic orders-postgres-auth --from-literal=POSTGRES_PASSWORD="$password" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  unset password
  echo "[PASS] New synthetic Postgres password created in $ns."
fi
