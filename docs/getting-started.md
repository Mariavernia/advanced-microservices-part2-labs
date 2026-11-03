# Getting started — GitHub Codespaces + AKS

The course is designed to run entirely from the browser.

## 1. Work from your personal fork

Use the fork assigned to you for this course. Your work, commits and GitHub Actions belong to that fork rather than to the instructor repository.

## 2. Create a Codespace

From your fork, choose **Code → Codespaces → Create codespace on main**.

The repository contains `.devcontainer/devcontainer.json`, which prepares the tools used throughout the course, including Java, Maven, Python, Azure CLI, `kubectl`, `kubelogin`, Helm, `curl`, HTTPie, `jq` and `yq`.

The Codespace is a development workstation. Kubernetes workloads run in the shared AKS cluster, not inside the Codespace.

## 3. Authenticate

Run:

```bash
./scripts/login.sh
```

The script uses Microsoft Entra ID device-code authentication, obtains user credentials for the course AKS cluster, converts the kubeconfig for Azure CLI authentication and sets your personal namespace as the default namespace of the current context.

It does not store an Azure password, Kubernetes service-account token or administrative kubeconfig in the repository.

## 4. Validate the environment

Run:

```bash
./scripts/preflight.sh
```

The CORE preflight validates the workstation, Azure authentication, Kubernetes API, namespace and the permissions that matter at the start of the course.

The instructor can additionally run:

```bash
./scripts/preflight.sh --full
```

when validating shared services such as Grafana, Jaeger, Kibana, Keycloak, cluster DNS and the registry endpoint.

## 5. Start P00

Open:

```text
labs/p00-kubernetes-survival-kit/README.md
```

Do not deploy resources into a namespace other than the one selected by `login.sh`.

## Troubleshooting boundary

If `preflight.sh` fails before you modify any lab manifest, treat it as an environment or access problem. Do not change the P00 YAML to compensate for authentication, RBAC or cluster configuration errors.
