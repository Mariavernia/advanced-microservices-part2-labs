#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${ROOT_DIR}/config/course.env"

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

require_value() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "[ERROR] ${name} is not configured." >&2
    echo "        The instructor must complete config/course.env before the course." >&2
    exit 1
  fi
}

for variable in AZURE_TENANT_ID AKS_RESOURCE_GROUP AKS_NAME; do
  require_value "${variable}"
done

for command in az kubectl kubelogin; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "[ERROR] Required command not found: ${command}" >&2
    echo "        Rebuild the Codespace/dev container and try again." >&2
    exit 1
  fi
done

CURRENT_TENANT=""
if az account show >/dev/null 2>&1; then
  CURRENT_TENANT="$(az account show --query tenantId -o tsv 2>/dev/null || true)"
fi

if [[ "${CURRENT_TENANT}" != "${AZURE_TENANT_ID}" ]]; then
  echo "Authenticating with Microsoft Entra ID..."
  az login --tenant "${AZURE_TENANT_ID}" --use-device-code --output none
else
  echo "Azure session already authenticated for the course tenant."
fi

if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
  az account set --subscription "${AZURE_SUBSCRIPTION_ID}"
fi

echo "Retrieving AKS user credentials..."
az aks get-credentials \
  --resource-group "${AKS_RESOURCE_GROUP}" \
  --name "${AKS_NAME}" \
  --overwrite-existing \
  --output none

kubelogin convert-kubeconfig -l azurecli

UPN="$(az account show --query user.name -o tsv)"
DERIVED_NAMESPACE="${UPN%%@*}"
STUDENT_NAMESPACE="${STUDENT_NAMESPACE:-${DERIVED_NAMESPACE}}"

if [[ ! "${STUDENT_NAMESPACE}" =~ ^student[0-9]{2}$ && "${STUDENT_NAMESPACE}" != "demo" ]]; then
  cat >&2 <<EOF_ERROR
[ERROR] Could not derive a valid course namespace from the authenticated identity.
        Azure identity: ${UPN}
        Derived value:  ${DERIVED_NAMESPACE}

Student accounts should use names such as student07@...
For an instructor/demo account, set STUDENT_NAMESPACE=demo explicitly.
EOF_ERROR
  exit 1
fi

if [[ "$(kubectl auth can-i get pods --namespace "${STUDENT_NAMESPACE}" 2>/dev/null)" != "yes" ]]; then
  echo "[ERROR] The authenticated identity cannot access pods in namespace ${STUDENT_NAMESPACE}." >&2
  echo "        Check the student assignment and Kubernetes RoleBinding." >&2
  exit 1
fi

kubectl config set-context --current --namespace="${STUDENT_NAMESPACE}" >/dev/null

cat <<EOF_OK

Login complete.

  Azure identity : ${UPN}
  AKS cluster    : ${AKS_NAME}
  Namespace      : ${STUDENT_NAMESPACE}

Next step:
  ./scripts/preflight.sh

EOF_OK
