# P05 — Proteger una API con OAuth 2.0, OIDC, JWT y Keycloak

**Modalidad:** individual desde Codespaces, con una práctica guiada basada en la
misma Advanced Orders Platform. **Prerequisito:** P01 operativo y Keycloak
compartido configurado por el instructor. **Sin instalaciones locales.** Sigue [la metodología de prácticas](../../docs/METODOLOGIA-PRACTICAS.md): predicción, exploración, diagnóstico y evidencia. Los scripts de autenticación evitan manejar credenciales manualmente; no son la solución intelectual de la práctica.

## Problema

P01 permitió llamar a todas las rutas del Gateway sin autenticar. Ahora
necesitamos distinguir **identidad del cliente**, **integridad del token** y
**autorización para cada operación**.

El Gateway actuará como **OAuth 2.0 Resource Server**. Keycloak será el
proveedor OIDC compartido. No instalaremos Keycloak en el namespace del alumno.
La autorización por roles ocurrirá en el Gateway y no en el código de negocio.

## Objetivos CORE

- Diferenciar OAuth 2.0 (delegación/autorización), OIDC (identidad) y JWT
  (formato de token). No son sinónimos.
- Explicar por qué decodificar base64 no verifica la firma de un JWT.
- Obtener un token sin escribir contraseñas ni secretos en Git (Device Authorization Grant).
- Interpretar los códigos HTTP **401**, **403** y **200** con evidencia.
- Leer las reglas de autorización y localizar roles de Keycloak.
- Reconocer el límite de proteger solo el Gateway cuando existen rutas internas.

## Preparación del instructor (dependencia externa)

El instructor debe proporcionar:

- Keycloak **HTTPS**, accesible desde el navegador/Codespaces y desde AKS.
- Un realm OIDC con URL de issuer exacta en `config/course.env`:
  `OIDC_ISSUER_URI=https://.../realms/advanced-orders`.
- Client **público** `advanced-orders-cli`, con Device Authorization Grant
  habilitado y mapeo del público `aud` = `advanced-orders-api`.
- Usuarios de práctica con roles realm `orders-reader` y `platform-admin`.
- La imagen `advancedorders/api-gateway:0.2.0-sec` publicada en ACR por el instructor.
- Los alumnos no administran el realm ni conocen credenciales administrativas.

Si alguno de estos requisitos falta, **P05 no está preparado para ejecutarse**.
No cambies el Gateway anterior para intentar compensar un problema de identidad.

## CORE 1 — Antes y después de proteger una ruta

Inspecciona estos archivos:

- `services/api-gateway/src/main/java/com/advancedorders/apigateway/security/GatewaySecurityConfiguration.java`
- `services/api-gateway/src/main/resources/application-p05-security.yml`
- `manifests/01-api-gateway-secure.yaml`

¿Qué ocurre cuando `SPRING_PROFILES_ACTIVE=p05-security`? ¿Por qué la aplicación
P00–P04 no se protege automáticamente al compilar el código de P05?

**No ejecutes todavía ningún verificador.** Inspecciona las reglas de autorización del Gateway, el mapeo de `realm_access.roles` y las condiciones de validación de JWT (issuer y audience). Predice qué respuestas recibirán tres peticiones a `/api/payments/methods`:
sin token, con usuario lector y con administrador. Escribe además qué parte se debe a autenticación y cuál a autorización.

## CORE 2 — Preparar y desplegar el Gateway protegido

**No recrees los seis servicios:** solo cambiaremos la revisión del Gateway.

```bash
./scripts/preflight.sh
bash labs/p01-complete-platform/scripts/verify.sh
bash labs/p05-api-security/scripts/deploy.sh
kubectl get deployment api-gateway
kubectl describe deployment api-gateway
```

Este **helper prepara la integración**, pero no resuelve el ejercicio: después de ejecutarlo, debes abrir el Deployment y localizar por tu cuenta la imagen, el perfil activo, las variables OIDC y las sondas de salud. Explica qué cambiaría si el emisor anunciado por Keycloak no coincide con el emisor configurado.

El script valida el OIDC metadata y crea un ConfigMap con identificadores
**no secretos**. El manifiesto usa la imagen distinta `0.2.0-sec` y activa
`p05-security`. Si la imagen no existe, debes informar al instructor: no
hagas builds ni cambios administrativos en el ACR.

## CORE 3 — Observar un HTTP 401 sin credenciales

Abre otra terminal y mantén activo:

```bash
kubectl port-forward service/api-gateway 8080:8080
```

Desde una segunda terminal:

```bash
curl -i 'http://localhost:8080/api/orders/preview?sku=SKU-001&quantity=2'
curl -i 'http://localhost:8080/actuator/health'
```

Esperado: Orders sin token → **401**; health check → **200**.
La disponibilidad del proceso no debe depender de iniciar sesión como usuario.

## CORE 4 — Obtener tokens mediante Device Authorization Grant

**No uses usuarios o contraseñas en scripts.** El instructor facilitará las
cuentas de práctica. El código del dispositivo se valida en el navegador.

```bash
bash labs/p05-api-security/scripts/device-login.sh reader
bash labs/p05-api-security/scripts/device-login.sh admin
```

Ambos tokens quedan en archivos privados dentro de `~/.cache/advanced-orders`,
fuera de Git, sin mostrarse en terminal. Usa una cuenta Keycloak con el rol
correspondiente para cada autenticación. No compartas estos archivos.

## CORE 5 — 401 frente a 403: interpreta el control de acceso

**Antes de ejecutar el verificador**, prepara una tabla con tus predicciones sobre cinco peticiones (sin copiar ni imprimir tokens). Examina las reglas Java y la configuración del cliente. La obtención y manejo de JWT se mantiene en helpers seguros para no exponer credenciales en el historial del shell, capturas o argumentos de procesos. **No intentes extraer ni pegar los JWT** para hacer peticiones manuales.

Con `port-forward` activo, ejecuta al final la comprobación HTTP segura:

```bash
bash labs/p05-api-security/scripts/verify.sh
```

Completa la tabla con los resultados reales y señala, para cada respuesta, la regla o condición que la explica:

| Petición | Evidencia prevista |
|---|---|
| Orders sin token | 401 |
| Actuator health sin token | 200 |
| Orders con `orders-reader` | 200 |
| Payments con `orders-reader` | 403 |
| Payments con `platform-admin` | 200 |

**401:** no hay un token válido para autenticar la petición.  
**403:** el cliente se ha autenticado, pero no tiene autorización.

**Checkpoint de investigación:** distingue un rechazo por JWT inválido (401), un rechazo por privilegios insuficientes (403) y una autorización exitosa (200). En cada caso identifica la evidencia disponible en política, HTTP y logs, evitando mostrar el valor del JWT.

Inspecciona cómo se convierten los roles Keycloak `realm_access.roles` a
autoridades de Spring. ¿Qué ocurriría si todos los usuarios recibieran el rol
`platform-admin`?

## CORE 6 — Analizar las garantías de seguridad

Un JWT debe ser validado por el receptor: firma, emisor (`iss`),
audiencia (`aud`) y tiempos (`exp`, `nbf`) según aplique. Los
`scopes` y `roles` se interpretan **después** de esas validaciones.

La demo usa port-forward al Gateway. Pregunta crítica: ¿podría otro Pod del
mismo namespace invocar Orders directamente, sin pasar por el Gateway?

**Sí, salvo que existan controles adicionales que lo impidan.** Proteger solo
el Gateway no es protección completa entre workloads. P06 introducirá controles
en la malla y políticas de red. No afirmes que se ha logrado seguridad extremo
a extremo por comprobar únicamente 401 y 403 en el Gateway.

## SUPPORT

```bash
kubectl logs deployment/api-gateway --tail=50
kubectl describe pod -l app.kubernetes.io/name=api-gateway
kubectl get configmap p05-security-settings
kubectl get endpointslice -l kubernetes.io/service-name=api-gateway
```

Diagnóstico por síntoma:
- `ImagePullBackOff`: falta imagen o pull desde ACR.
- `issuer mismatch`: hostname/issuer declarado no coincide con Keycloak.
- `401` con token: firma, tiempo, issuer o audiencia pueden ser incorrectos.
- `403` con token: revisar el mapeo de roles y la regla del endpoint.
- `502` con token válido: puede ser un upstream caído, no un error OIDC.

**Nunca pegues JWT en un chat, issue, commit o captura.**

## STRETCH

Propón controles adicionales: validación de audiencia en servicios internos,
NetworkPolicy que impida el bypass, gateway TLS, autorización de mínimo privilegio,
Keycloak accesible con HA, registro de fallos de autorización sin datos sensibles
y gestión de rotación de claves JWT.

## Evidencia de cierre

Entrega cuatro frases: **predije, cambié/inspeccioné, observé, concluyo**. Incluye la tabla 401/403/200 con su causa, una captura o referencia a la regla de autorización y un límite de seguridad que **no** resuelve la protección del Gateway. Ejecutar el script de verificación sin poder justificar los resultados no completa P05.

## Cierre y recuperación

```bash
bash labs/p05-api-security/scripts/cleanup.sh
rm -f ~/.cache/advanced-orders/reader.jwt ~/.cache/advanced-orders/admin.jwt
```

El cleanup restaura la imagen y configuración del Gateway de P01 en tu namespace.
No modifica el Keycloak compartido ni los datos de otros alumnos.

**Estado de aceptación:** implementación preparada en rama, pendiente de
Keycloak compartido, imagen `0.2.0-sec` y ensayo real AKS/Device Grant.
