# Guía del alumno — Primeros pasos

**Arquitectura de Microservicios Avanzada · Parte 2: Orquestación, Seguridad y Observabilidad**  
Global Knowledge / Indra · 16–20 de noviembre de 2026 · 09:00–15:00 (hora de España)

Esta guía es el punto de entrada al curso. Léela antes de comenzar P00. Trabajaremos sobre **Advanced Orders Platform**, una aplicación de seis microservicios Java/Spring Boot que evolucionará a lo largo de ocho prácticas. El objetivo es aprender a desplegar, operar, proteger y diagnosticar microservicios; no aprender Java desde cero.

## 1. Qué necesitas y qué recibirás

Necesitas un navegador actualizado, conexión a Internet, una cuenta GitHub y poder abrir sesiones privadas del navegador. No necesitas instalar Docker, Java, Maven, Azure CLI, Kubernetes ni VS Code en tu ordenador. El instructor facilitará los accesos de forma individual.

| Acceso | Ejemplo (no son credenciales) | Para qué sirve |
|---|---|---|
| GitHub | Tu cuenta personal autorizada | Repositorio privado, fork, Codespaces y CI |
| Microsoft Entra ID | studentNN@training.cloudsecurityinpractice.com | Autenticación Azure y AKS |
| Namespace Kubernetes | studentNN | Tu espacio de trabajo aislado |
| Keycloak — Reader | studentNN-reader | P05: consultar pedidos |
| Keycloak — Admin | studentNN-admin | P05: acceder a operaciones de Payments |

NN es tu número asignado, por ejemplo 07. No elijas otro número ni uses cuentas de compañeros. Las contraseñas de Entra y Keycloak se entregan por un canal privado; no están en GitHub. El rol de aplicación Admin de Keycloak no es administrador de Azure, Kubernetes ni del propio Keycloak.

Antes de la primera sesión, confirma que puedes iniciar sesión en GitHub, aceptar la invitación al repositorio privado y utilizar Codespaces con tu cuenta. Si GitHub solicita un método de pago o muestra que has agotado tu cuota, avisa al instructor antes de contratar nada. Las condiciones y consumo de Codespaces dependen de tu cuenta y del plan de facturación. La infraestructura Azure la gestiona el instructor.

## 2. Qué está preparado en la infraestructura

- **AKS compartido:** un clúster Kubernetes real en Azure, con varios nodos de trabajo y servicios de plataforma. El instructor lo enciende para las clases y puede apagarlo fuera de ellas.
- **Tu namespace:** ya creado, inicialmente sin aplicaciones ni bases de datos. Puedes gestionar los recursos permitidos de tu namespace, no los de otros alumnos. Tiene RBAC, ResourceQuota, LimitRange y NetworkPolicy de aislamiento. Los ConfigMaps de certificados automáticos son normales y no se borran.
- **ACR:** las imágenes de los seis microservicios ya existen. Kubernetes puede descargarlas mediante su propia identidad; no necesitas credenciales del registro.
- **Keycloak:** servicio de identidad compartido con HTTPS y usuarios individuales. Lo utilizaremos en P05.
- **Istio:** malla instalada y administrada por el instructor. En P06 se activará selectivamente en Orders e Inventory de cada alumno.
- **PostgreSQL, Redis y Jaeger de laboratorio:** todavía no están desplegados en tu namespace. Los crearás en P04 y P07. Son distintos de la base de datos interna de Keycloak.

```text
Tu navegador
  |-- GitHub -> tu fork -> Codespace (terminal y editor web)
  |                          |
  |                          +-- Entra ID -> API de Kubernetes
  |                                            |
  |                                            +-- tu namespace studentNN
  |                                                Gateway, Orders, Inventory,
  |                                                Payments, Shipping, Notifications
  |
  +-- Keycloak HTTPS (P05)
  +-- Puertos privados de Codespaces (Gateway / Jaeger)
```

El Codespace es tu puesto de trabajo remoto; los Pods se ejecutan en AKS, no en el Codespace. Cerrar el Codespace no elimina los Pods.

## 3. Obtener el repositorio y crear tu Codespace

1. Inicia sesión en [GitHub](https://github.com).
2. Acepta la invitación que te haya enviado el instructor. Abre el [repositorio del curso](https://github.com/pacosepulveda/advanced-microservices-part2-labs). Si aparece 404, comprueba primero la cuenta GitHub y la invitación; no crees un repositorio alternativo.
3. Pulsa **Fork** y crea tu fork personal, manteniendo el nombre del repositorio. Si ya existe, abre tu fork y utiliza **Sync fork → Update branch** para actualizar main antes de empezar. Si hay conflictos o cambios propios, no los descartes sin consultar.
4. En tu fork, selecciona la rama **main**, pulsa **Code → Codespaces → Create codespace on main**.
5. Espera a que VS Code Web termine la preparación del Dev Container. Utiliza la configuración y tamaño de máquina predeterminados salvo indicación del instructor.
6. Abre **Terminal → New Terminal**. Deberías estar en el directorio del repositorio, habitualmente /workspaces/advanced-microservices-part2-labs.

Comprueba:

```bash
pwd
git branch --show-current
git log -1 --oneline
ls labs
```

Debes ver main y ocho directorios P00–P07. El instructor indicará la versión de entrega; no necesitas cambiar de rama para empezar.

El Dev Container prepara Git, GitHub CLI, Azure CLI, kubectl, kubelogin, Helm, curl, HTTPie, jq, yq, Java, Maven y Python. Si falla la instalación, avisa antes de instalar herramientas manualmente. Puedes usar el menú de comandos de VS Code Web para **Codespaces: Rebuild Container** si el instructor lo indica.

## 4. Primer acceso a Azure y AKS

Ejecuta desde la raíz del repositorio:

```bash
./scripts/login.sh
```

El script iniciará autenticación Microsoft Entra mediante código de dispositivo si no hay sesión válida del tenant del curso.

1. Abre la URL Microsoft que aparece en la terminal (normalmente https://login.microsoft.com/device).
2. Introduce el código generado en esa ejecución. No lo compartas con nadie.
3. Selecciona **usar otra cuenta** si el navegador tiene una sesión personal abierta. Autentícate con tu cuenta studentNN@training.cloudsecurityinpractice.com, no con la cuenta GitHub ni con Keycloak.
4. Completa cambio de contraseña temporal o MFA si Entra lo solicita. No compartas ningún código MFA.
5. Si Azure CLI presenta una selección de suscripción, elige **Plataformas de MSDN** del curso (o pulsa Enter si ya está seleccionada).
6. Regresa a la terminal. El script obtendrá un kubeconfig de usuario y seleccionará tu namespace.

Ejemplo esperado para student07:

```text
Login complete.

  Azure identity : student07@training.cloudsecurityinpractice.com
  AKS cluster    : aks-advms26-course
  Namespace      : student07
```

Comprueba tu identidad y espacio:

```bash
az account show --query user.name -o tsv
kubectl config current-context
kubectl config view --minify -o jsonpath='{..namespace}'; echo
kubectl get pods
```

Al inicio, "No resources found in student07 namespace" es correcto. Si aparece otro usuario o namespace, detente. No uses --admin, no cambies manualmente al namespace de un compañero y no solicites sus credenciales.

### Si ya había una sesión Azure en el Codespace

El script puede reutilizar una sesión del mismo tenant. Si la identidad es incorrecta, cierra la sesión y repite el login con tu cuenta asignada:

```bash
az logout
./scripts/login.sh
```

Utiliza un Codespace personal para evitar mezclar sesiones. Si el clúster está apagado, el instructor deberá arrancarlo; no cambies los identificadores de config/course.env.

## 5. Validar que todo funciona

```bash
./scripts/preflight.sh
```

El preflight CORE comprueba herramientas, identidad, acceso al API Kubernetes, namespace, permisos y Helm. El resultado esperado es:

```text
=== SUMMARY ===
PASS: 26  FAIL: 0  WARN: 0  SKIP: 0
```

El número de checks podría variar si se actualiza el script; lo importante es no tener fallos. Las comprobaciones de operaciones que **deben estar denegadas** cuentan como PASS cuando se rechazan correctamente.

No ejecutes el modo --full para solucionar un fallo CORE: comprueba endpoints compartidos opcionales y no es un requisito de P00. Si hay un FAIL, guarda el mensaje sin credenciales y avisa al instructor antes de modificar manifiestos.

## 6. Cómo vamos a trabajar

Abre cada README en VS Code Web. Sigue el orden indicado por el instructor; no ejecutes todos los scripts de golpe.

| Práctica | Qué harás | Qué conservar |
|---|---|---|
| [P00 — Survival Kit](../labs/p00-kubernetes-survival-kit/README.md) | Orders e Inventory, Pods, Services, DNS, escalado y diagnóstico | Baseline para P01 |
| [P01 — Plataforma completa](../labs/p01-complete-platform/README.md) | Seis servicios, configuración, Secret sintético y rutas Gateway | Seis servicios operativos |
| [P02 — Resiliencia](../labs/p02-resilience/README.md) | Probes, requests/limits, HPA y [alta disponibilidad](../labs/p02-resilience/HA-BALANCEO.md) | Restaurar la escala/estado indicado antes de P03 |
| [P03 — CI y rollouts](../labs/p03-rollouts-ci/README.md) | Revisiones, fallo controlado y rollback | Recuperar la operación de negocio |
| [P04 — Estado y caché](../labs/p04-state-and-cache/README.md) | PostgreSQL con PVC, Redis e invalidación de caché | Seguir las instrucciones de cierre |
| [P05 — Seguridad API](../labs/p05-api-security/README.md) | Gateway seguro, OAuth Device Grant, roles y códigos HTTP | Gateway protegido para P06/P07 |
| [P06 — Service Mesh](../labs/p06-service-mesh/README.md) | mTLS entre Orders e Inventory, política STRICT y evidencia | Conservar inyección; retirar política temporal según guía |
| [P07 — Observabilidad](../labs/p07-observability/README.md) | Jaeger, OpenTelemetry, métricas, trazas y logs, incidente reversible | Restaurar latencia a cero |

En cada práctica: **predice → cambia → observa → concluye**. CORE es el recorrido común, SUPPORT ofrece ayuda y STRETCH permite profundizar si has terminado el CORE. Los scripts de verificación comprueban resultados, no sustituyen tus observaciones. Consulta [la metodología](METODOLOGIA-PRACTICAS.md).

Las seis aplicaciones se ejecutan con datos sintéticos. No hay pagos, envíos ni notificaciones reales. P04 demuestra almacenamiento y caché con psql/redis-cli, no una integración de persistencia en la API Java de Orders. P03 tiene CI en GitHub Actions, no CD automático de los forks a AKS.

## 7. Acceder a la aplicación desde Codespaces

Cuando P01 haya creado el Gateway, puedes abrir dos terminales. En A:

```bash
kubectl port-forward service/api-gateway 8080:8080
```

En B:

```bash
curl -fsS 'http://127.0.0.1:8080/api/orders/preview?sku=SKU-001&quantity=2' | jq
```

Antes de P05 se espera una respuesta JSON de negocio con canBeFulfilled=true. Desde P05 el endpoint protegido exige token y sin él devuelve 401. El port-forward debe permanecer en ejecución; Ctrl+C lo detiene. En la pestaña **Ports** de VS Code Web mantén la visibilidad **Private**. No uses Make Public.

En P07 el mismo mecanismo permitirá consultar Jaeger:

```bash
kubectl port-forward service/p07-jaeger 16686:16686
```

Abre el puerto privado desde **Ports**. No expongas Jaeger ni las aplicaciones de alumno a Internet.

## 8. Las cuentas Keycloak (solo cuando lleguemos a P05)

El issuer del curso es https://auth.microservices.training.cloudsecurityinpractice.com/realms/advanced-orders. Tu identidad Entra no es una cuenta Keycloak. Recibirás dos usuarios de aplicación con sus propias contraseñas.

Tras desplegar el Gateway protegido siguiendo P05, deja el port-forward 8080 activo y ejecuta:

```bash
bash labs/p05-api-security/scripts/device-login.sh reader
```

Abre el enlace que genera esa ejecución en una ventana privada. Inicia sesión con studentNN-reader y autoriza la solicitud de dispositivo. Cierra todas las ventanas privadas de esa sesión una vez que el script confirme el token.

```bash
bash labs/p05-api-security/scripts/device-login.sh admin
```

Abre una nueva sesión privada y usa studentNN-admin. No reutilices la sesión del lector. Después:

```bash
bash labs/p05-api-security/scripts/verify.sh
```

| Prueba | HTTP esperado |
|---|---:|
| Orders sin token | 401 |
| Health sin token | 200 |
| Reader consulta Orders | 200 |
| Reader consulta Payments | 403 |
| Admin consulta Payments | 200 |

Los tokens se guardan fuera de Git, en ~/.cache/advanced-orders, con permisos privados. No los muestres con cat, no los copies a chats ni los subas a GitHub. Si hay access_denied o expiración, inicia un nuevo flujo; usa su código nuevo y la identidad correcta. Si tras repetir falla, avisa al instructor. Si el token ha expirado, repite el login del perfil correspondiente.

## 9. Incidencias frecuentes

| Síntoma | Qué comprobar o hacer |
|---|---|
| GitHub 404 / Fork no disponible | Cuenta correcta, invitación aceptada, acceso privado y política de forks |
| Codespace no inicia / cuota agotada | Estado de creación, cuenta GitHub, cuota y facturación; avisa al instructor |
| Azure login falla | Cuenta Entra del curso, contraseña temporal/MFA, tenant y suscripción; no compartas códigos |
| Forbidden en tu namespace | Identidad y namespace; informa del verbo/recurso denegado |
| Forbidden en otro namespace | Es el comportamiento esperado |
| API Kubernetes inaccesible | Confirma con instructor que AKS está Running; no intentes crear otro clúster |
| Pending / FailedScheduling | Describe el Pod y revisa eventos y quota; no aumentes límites |
| ImagePullBackOff | Revisa nombre/tag en README y eventos; instructor comprueba ACR |
| CrashLoopBackOff / no Ready | Logs, describe, probes y configuración; no borres todo |
| Port-forward ocupado o desconectado | Ctrl+C en el anterior, vuelve a abrir el puerto privado; revisa Pod Ready |
| P05 401/403 inesperado | Puerto correcto, token vigente, perfil y sesión privada; no desactives seguridad |
| P06 sin istio-proxy | Espera confirmación de activación selectiva; no etiquetes namespaces |
| P07 sin trazas | Jaeger Ready, agente y exportador OTLP, genera una petición y revisa filtros |

Comandos seguros de diagnóstico desde tu namespace:

```bash
kubectl get deployment,pod,service
kubectl get events --sort-by=.lastTimestamp | tail -n 20
kubectl describe pod <nombre-del-pod>
kubectl logs deployment/orders --tail=80
kubectl get resourcequota
```

Sustituye el marcador del nombre de Pod por el real. No envíes salida de Secrets, kubeconfig, tokens ni contraseñas. Para pedir ayuda indica tu número, práctica y paso, comando que falla, error exacto y observación esperada. No incluyas device codes ni datos privados.

## 10. Al terminar cada sesión

- Conserva el estado necesario para la práctica siguiente. No ejecutes cleanup general ni elimines PVC sin indicación del instructor.
- Guarda tus evidencias y cambios propios en el fork (sin secretos). Antes de commit, revisa git status y git diff.
- Detén los port-forwards con Ctrl+C.
- En [GitHub Codespaces](https://github.com/codespaces), elige **Stop codespace** cuando hayas acabado. Cerrar una pestaña no garantiza la parada inmediata. El almacenamiento puede seguir contando en tu cuota.
- No borres el Codespace salvo que hayas guardado tus cambios. Si lo recreas, deberás repetir login/preflight y recuperar tokens P05 si los necesitas; los recursos de AKS no se borran automáticamente.

El instructor administra arranque/parada de AKS, limpieza y accesos. No intentes detener, escalar o destruir la infraestructura común.

**Ya puedes comenzar [P00](../labs/p00-kubernetes-survival-kit/README.md) cuando el instructor lo indique.**
