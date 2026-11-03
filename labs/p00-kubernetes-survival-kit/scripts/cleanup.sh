#!/usr/bin/env bash
set -euo pipefail

kubectl delete -f "$(dirname "$0")/../manifests/04-orders-service.yaml" --ignore-not-found
kubectl delete -f "$(dirname "$0")/../manifests/03-orders-deployment.yaml" --ignore-not-found
kubectl delete -f "$(dirname "$0")/../manifests/02-inventory-service.yaml" --ignore-not-found
kubectl delete -f "$(dirname "$0")/../manifests/01-inventory-deployment.yaml" --ignore-not-found
