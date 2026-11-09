#!/usr/bin/env bash
set -euo pipefail

YQ_VERSION="v4.54.1"
KUBELOGIN_VERSION="v0.2.22"

sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ca-certificates curl dnsutils httpie jq unzip
sudo rm -rf /var/lib/apt/lists/*

case "$(dpkg --print-architecture)" in
  amd64)
    YQ_ARCH="amd64"
    KUBELOGIN_ARCH="amd64"
    KUBELOGIN_SHA256="716cbcb1880bca8f0e976b8917d06fcfe04de2c1e737eaaabbb26e2782330119"
    ;;
  arm64)
    YQ_ARCH="arm64"
    KUBELOGIN_ARCH="arm64"
    KUBELOGIN_SHA256="306a31d80af443d06fb71e04d2feaf65a6c9cf2e7e806e87b895b77fe2093ea6"
    ;;
  *)
    echo "Unsupported architecture: $(dpkg --print-architecture)" >&2
    exit 1
    ;;
esac

if ! command -v yq >/dev/null 2>&1; then
  curl -fsSL \
    "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${YQ_ARCH}" \
    -o /tmp/yq
  sudo install -m 0755 /tmp/yq /usr/local/bin/yq
fi

if ! command -v kubelogin >/dev/null 2>&1; then
  KUBELOGIN_ZIP="/tmp/kubelogin.zip"
  curl -fsSL \
    "https://github.com/Azure/kubelogin/releases/download/${KUBELOGIN_VERSION}/kubelogin-linux-${KUBELOGIN_ARCH}.zip" \
    -o "${KUBELOGIN_ZIP}"
  echo "${KUBELOGIN_SHA256}  ${KUBELOGIN_ZIP}" | sha256sum -c -
  rm -rf /tmp/kubelogin
  unzip -q "${KUBELOGIN_ZIP}" -d /tmp/kubelogin
  sudo install -m 0755 \
    "/tmp/kubelogin/bin/linux_${KUBELOGIN_ARCH}/kubelogin" \
    /usr/local/bin/kubelogin
fi

# Git stores execute bits for all .sh scripts; avoid modifying tracked files.

cat <<'SUMMARY'

Advanced Orders Platform Codespace ready.

Next steps:
  1. ./scripts/login.sh
  2. ./scripts/preflight.sh
  3. Open labs/p00-kubernetes-survival-kit/README.md

SUMMARY
