# ADR-003 — P05: JWT validation and route-level authorization at API Gateway

**Status:** implementation staged; provider integration pending.

## Decision

Treat API Gateway as an OAuth 2.0 resource server. Use Spring Security to verify
signed JWT access tokens against Keycloak's OIDC issuer and an expected audience.
Map Keycloak realm roles to local authorities and differentiate `orders-reader`
from `platform-admin`. Browser/CLI signs in using Device Authorization Grant
with a **public client**: no client secret is distributed to students.

P00–P04 retain the legacy unsigned/unprotected demo Gateway image tag 0.1.0.
P05 must use a separately built image `api-gateway:0.2.0-sec`; selecting the
`p05-security` Spring profile activates JWT security and avoids changing prior labs.

## Known limits

- Authentication **at the Gateway** is not sufficient if Orders/Inventory remain
  directly accessible to untrusted callers. P06 will address workload-to-workload
  policies and/or network isolation as defense in depth.
- The shared Keycloak issuer, public client and classroom users are **not** provisioned
  by a student. They must exist prior to starting P05; stable HTTPS/DNS and trust
  are required both from Codespaces and AKS.
- We do not check tokens by base64 decoding alone; JWT verification requires
  signature, issuer, audience and timestamp validation.
- The Keycloak authorization **roles** are realm roles. Different providers might
  use scopes or resource/client roles and require different mappings.
- No password grant, client secret or Keycloak admin password belongs in Git.
- Both the protected API image and the shared Keycloak service require separate
  AKS end-to-end validation before accepting P05 for classroom use.
