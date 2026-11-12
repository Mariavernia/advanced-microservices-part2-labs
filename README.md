# Advanced Orders Platform

**Arquitectura de Microservicios Avanzada — Parte 2: Orquestación, Seguridad y Observabilidad**

Curso práctico sobre Kubernetes, Azure AKS, Spring Boot, OAuth/OIDC, Istio y observabilidad distribuida. Partimos de dos servicios síncronos y evolucionamos hacia seis microservicios; cada práctica introduce un problema observable y el mecanismo que lo resuelve.

## Empezar aquí

Trabaja desde tu **fork personal** con **GitHub Codespaces**. No necesitas instalar herramientas en tu ordenador. El instructor facilita tu identidad Entra ID, namespace y cuentas de aplicación para P05.

1. Abre tu fork y crea un Codespace desde `main`.
2. Ejecuta `./scripts/login.sh` y `./scripts/preflight.sh`.
3. Comprueba que el namespace seleccionado es el tuyo.
4. Comienza por [P00](labs/p00-kubernetes-survival-kit/README.md).

Guía completa: [Primeros pasos](docs/getting-started.md). Metodología: [predicción, cambio, observación y conclusión](docs/METODOLOGIA-PRACTICAS.md).

## Recorrido de laboratorios

| Práctica | Contenido |
|---|---|
| [P00](labs/p00-kubernetes-survival-kit/README.md) | Deployment, Service, DNS, Pods y escalado |
| [P01](labs/p01-complete-platform/README.md) | Plataforma de seis servicios, Gateway, configuración y recursos |
| [P02](labs/p02-resilience/README.md) | Probes, resiliencia, HPA y alta disponibilidad |
| [P03](labs/p03-rollouts-ci/README.md) | Rolling updates, rollback y CI |
| [P04](labs/p04-state-and-cache/README.md) | PostgreSQL, PVC, Redis y caché |
| [P05](labs/p05-api-security/README.md) | Keycloak, OAuth/OIDC, JWT y autorización |
| [P06](labs/p06-service-mesh/README.md) | Istio, Envoy y mTLS |
| [P07](labs/p07-observability/README.md) | OpenTelemetry, Jaeger, métricas, logs e incidente |

El recorrido CORE P00–P07 ha sido ensayado con identidades reales de alumno en Codespaces y AKS. La preparación de la cohorte de 16 y su ensayo concurrente son comprobaciones independientes del instructor.

**No ejecutes todos los laboratorios de golpe.** Mantén los servicios que pide la práctica siguiente. Los verificadores se ejecutan al final y no sustituyen las evidencias. No compartas contraseñas, JWT, kubeconfig ni archivos privados de credenciales.

## Imágenes y arquitectura

El ACR del curso es `advms26acr4366001b.azurecr.io`. El instructor publica las imágenes; no necesitas permisos de escritura en el registro.

- Baseline: Orders `0.1.1`; Inventory, Gateway, Payments, Shipping y Notifications `0.1.0`.
- P05: Gateway protegido `0.2.0-sec`.
- P07: Inventory `0.1.0-p07` con latencia de entrenamiento desactivada por defecto.

Java 21, Spring Boot 4.1.2, Maven, Kubernetes, Azure CLI, kubelogin y Helm. P04 utiliza PostgreSQL y Redis para observar persistencia y caché; no presupone que Orders Java persista sus datos. No se realizan pagos, envíos ni notificaciones reales.

## Comandos útiles

```bash
make login
make preflight
make test
make package
make p00-verify
```

La ejecución local con Docker es opcional y no es necesaria para el curso. El AKS compartido debe estar iniciado por el instructor.
