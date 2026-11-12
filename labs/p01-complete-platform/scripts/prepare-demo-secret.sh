#!/usr/bin/env bash
set -euo pipefail
# P01 uses a deliberately artificial, randomly generated provider token.
# Never put authentic provider credentials in the student repository.
NS="$(kubectl config view --minify -o jsonpath='{..namespace}')"
[[ "$NS" =~ ^student[0-9]{2}$ || "$NS" == "demo" ]] || { echo "Unexpected namespace: $NS" >&2; exit 1; }
TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(24))')"
kubectl create secret generic notifications-provider \
  --from-literal=NOTIFICATION_PROVIDER_TOKEN="$TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
unset TOKEN
echo "[PASS] Synthetic provider Secret created in namespace $NS"
echo "No real credential was created, logged or committed."
