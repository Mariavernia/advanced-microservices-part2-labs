#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${ROOT_DIR}/config/course.env"
FULL=false

if [[ "${1:-}" == "--full" ]]; then
  FULL=true
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--full]" >&2
  exit 2
fi

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
WARN_COUNT=0

pass() { printf '[PASS] %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '[FAIL] %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { printf '[SKIP] %s\n' "$1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }
warn() { printf '[WARN] %s\n' "$1"; WARN_COUNT=$((WARN_COUNT + 1)); }

check_command() {
  local command="$1"
  local label="${2:-$1}"
  if command -v "${command}" >/dev/null 2>&1; then
    pass "Tool available: ${label}"
  else
    fail "Tool missing: ${label}"
  fi
}

expect_can_i() {
  local expected="$1"
  local description="$2"
  shift 2
  local result
  result="$(kubectl auth can-i "$@" 2>/dev/null || true)"
  if [[ "${result}" == "${expected}" ]]; then
    pass "${description} (${expected})"
  else
    fail "${description}: expected ${expected}, got ${result:-error}"
  fi
}

check_url() {
  local label="$1"
  local url="$2"
  if [[ -z "${url}" ]]; then
    skip "${label}: endpoint not configured yet"
    return
  fi

  local code
  code="$(curl --connect-timeout 5 --max-time 10 -sS -o /dev/null -w '%{http_code}' "${url}" 2>/dev/null || true)"
  if [[ "${code}" =~ ^[234][0-9][0-9]$ ]]; then
    pass "${label}: reachable over TLS/HTTP (${code})"
  else
    fail "${label}: not reachable (${code:-no response})"
  fi
}

printf '\n=== CORE PREFLIGHT ===\n\n'

if [[ "${CODESPACES:-false}" == "true" ]]; then
  pass "GitHub Codespaces environment"
else
  warn "Not running in GitHub Codespaces (allowed for instructor testing)"
fi

for item in \
  'git:Git' \
  'gh:GitHub CLI' \
  'az:Azure CLI' \
  'kubectl:kubectl' \
  'kubelogin:kubelogin' \
  'helm:Helm' \
  'curl:curl' \
  'http:HTTPie' \
  'jq:jq' \
  'yq:yq' \
  'java:Java' \
  'mvn:Maven' \
  'python3:Python'; do
  check_command "${item%%:*}" "${item#*:}"
done

if az account show >/dev/null 2>&1; then
  AZ_USER="$(az account show --query user.name -o tsv 2>/dev/null || true)"
  pass "Azure authentication (${AZ_USER})"
else
  fail "Azure authentication — run ./scripts/login.sh"
fi

if kubectl version --request-timeout=5s >/dev/null 2>&1; then
  pass "Kubernetes API reachable"
else
  fail "Kubernetes API unreachable — run ./scripts/login.sh"
fi

CURRENT_NAMESPACE="$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null || true)"
if [[ "${CURRENT_NAMESPACE}" =~ ^student[0-9]{2}$ || "${CURRENT_NAMESPACE}" == "demo" ]]; then
  pass "Course namespace selected (${CURRENT_NAMESPACE})"
else
  fail "Unexpected or missing namespace (${CURRENT_NAMESPACE:-none})"
fi

if [[ -n "${CURRENT_NAMESPACE}" ]]; then
  expect_can_i yes "Create Deployments in own namespace" create deployments.apps --namespace "${CURRENT_NAMESPACE}"
  expect_can_i yes "Delete Deployments in own namespace" delete deployments.apps --namespace "${CURRENT_NAMESPACE}"
  expect_can_i yes "Read Pod logs in own namespace" get pods/log --namespace "${CURRENT_NAMESPACE}"
  expect_can_i yes "Read EndpointSlices in own namespace" list endpointslices.discovery.k8s.io --namespace "${CURRENT_NAMESPACE}"
  expect_can_i yes "Read Pod metrics in own namespace" list pods.metrics.k8s.io --namespace "${CURRENT_NAMESPACE}"
  expect_can_i no  "Create Namespaces" create namespaces
  expect_can_i no  "Create ClusterRoles" create clusterroles.rbac.authorization.k8s.io

  if [[ "${CURRENT_NAMESPACE}" == "student01" ]]; then
    OTHER_NAMESPACE="student02"
  else
    OTHER_NAMESPACE="student01"
  fi
  expect_can_i no "Delete Deployments in another student namespace (${OTHER_NAMESPACE})" \
    delete deployments.apps --namespace "${OTHER_NAMESPACE}"
fi

if helm version --short >/dev/null 2>&1; then
  pass "Helm operational"
else
  fail "Helm is not operational"
fi

if [[ "${FULL}" == "true" ]]; then
  printf '\n=== FULL PLATFORM PREFLIGHT ===\n\n'

  if [[ -n "${CURRENT_NAMESPACE}" ]]; then
    DNS_POD="course-preflight-dns-${RANDOM}"
    DNS_OUTPUT="$(kubectl run "${DNS_POD}" \
      --image=busybox:1.36.1 \
      --restart=Never \
      --rm -i \
      --command -- nslookup kubernetes.default.svc.cluster.local 2>&1 || true)"
    if grep -Eq '(^|[[:space:]])Address:|Name:' <<<"${DNS_OUTPUT}"; then
      pass "Cluster DNS resolution from a workload"
    else
      fail "Cluster DNS resolution from a workload"
    fi
  fi

  check_url "Grafana" "${GRAFANA_URL:-}"
  check_url "Jaeger" "${JAEGER_URL:-}"
  check_url "Kibana" "${KIBANA_URL:-}"
  check_url "Keycloak" "${KEYCLOAK_URL:-}"

  if [[ -n "${ACR_LOGIN_SERVER:-}" ]]; then
    ACR_CODE="$(curl --connect-timeout 5 --max-time 10 -sS -o /dev/null -w '%{http_code}' \
      "https://${ACR_LOGIN_SERVER}/v2/" 2>/dev/null || true)"
    if [[ "${ACR_CODE}" == "200" || "${ACR_CODE}" == "401" ]]; then
      pass "Azure Container Registry endpoint reachable (${ACR_CODE})"
    else
      fail "Azure Container Registry endpoint unreachable (${ACR_CODE:-no response})"
    fi
  else
    skip "Azure Container Registry endpoint not configured yet"
  fi
else
  printf '\nShared platform checks are not required for P00.\n'
  printf 'Run %s --full when validating the complete course platform.\n' "$0"
fi

printf '\n=== SUMMARY ===\n'
printf 'PASS: %d  FAIL: %d  WARN: %d  SKIP: %d\n' \
  "${PASS_COUNT}" "${FAIL_COUNT}" "${WARN_COUNT}" "${SKIP_COUNT}"

if (( FAIL_COUNT > 0 )); then
  exit 1
fi

exit 0
