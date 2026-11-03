# Dev container

This directory defines the browser-based development workstation used during the course.

The Codespace contains development and Kubernetes client tools. Course workloads run in the shared AKS cluster rather than inside the Codespace.

After the container is created, continue with:

```bash
./scripts/login.sh
./scripts/preflight.sh
```

Tool versions that are particularly sensitive for the course are pinned in `post-create.sh`; the remaining Dev Container Features are pinned to their major version and should be validated again during the final delivery-readiness check before the course.
