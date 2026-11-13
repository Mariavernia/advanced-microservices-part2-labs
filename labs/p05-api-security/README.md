# P05 — Proteger una API con OAuth 2.0, OIDC, JWT y rate limiting

**Modo:** individual, desde tu fork y Codespaces. **Prerequisito:** P01 operativo y Gateway estable; finaliza los experimentos de P03 antes de empezar. Keycloak HTTPS compartido y cuentas individuales preparados por el instructor. Sigue [la metodología](../../docs/METODOLOGIA-PRACTICAS.md).

## Escenario

Advanced Orders ofrece rutas de pedidos, inventario, envíos, pagos y notificaciones. Necesitas protegerlas, aplicar mínimo privilegio y limitar el consumo de una ruta de negocio sin confundir identidad, autorización y disponibilidad.

No instalarás Keycloak ni escribirás un Resource Server desde cero. Tu trabajo consiste en **configurar la integración, verificar la política, resolver un fallo de seguridad y ajustar un límite de peticiones**. Los helpers de autenticación y HTTP evitan exponer los JWT; no deciden qué pruebas realizar.

## CORE 1 — Reconoce el contrato de identidad

Desde la raíz del repositorio:

~~~bash
./scripts/preflight.sh
bash labs/p01-complete-platform/scripts/verify.sh
source config/course.env
curl -fsS --max-time 15 "$OIDC_ISSUER_URI/.well-known/openid-configuration" |
  jq '{issuer,jwks_uri,device_authorization_endpoint,token_endpoint}'
~~~

Identifica el issuer exacto, la URL de claves públicas JWKS y los dos endpoints del Device Grant. Comprueba que usan HTTPS. No uses curl -k, no cambies el realm, no añadas secretos al cliente público.

El instructor proporciona el client ID y la audiencia esperada en config/course.env. **La audiencia del recurso no es necesariamente el client ID**. Consulta los dos valores y explica qué representa cada uno.

Abre:
- services/api-gateway/src/main/java/com/advancedorders/apigateway/security/GatewaySecurityConfiguration.java
- services/api-gateway/src/main/resources/application-p05-security.yml
- labs/p05-api-security/manifests/01-api-gateway-secure.yaml

Localiza el perfil de seguridad, las reglas de rutas y el mapeo de roles. Predice las respuestas de Orders y Payments para una petición anónima, un lector y un administrador. ¿Qué rutas pueden acceder a health sin credenciales? ¿Qué ocurre con una ruta no contemplada en las reglas?

## CORE 2 — Configura el Resource Server

Crea tu configuración de trabajo:

~~~bash
mkdir -p work/p05
cp labs/p05-api-security/templates/security-settings.yaml work/p05/security-settings.yaml
~~~

Completa en el editor el issuer observado en discovery y la audiencia del recurso indicada en config/course.env. Son identificadores no secretos. No pongas la contraseña ni el client secret en el ConfigMap.

Abre el manifiesto del Gateway protegido. Comprueba la referencia al ConfigMap, la imagen 0.2.0-sec, el perfil p05-security y las probes. El helper deploy.sh queda reservado para recuperación; **no lo ejecutes como recorrido principal**.

~~~bash
kubectl apply --dry-run=server -f work/p05/security-settings.yaml
kubectl apply -f work/p05/security-settings.yaml
kubectl apply -f labs/p05-api-security/manifests/01-api-gateway-secure.yaml
kubectl rollout status deployment/api-gateway --timeout=300s
kubectl get configmap p05-security-settings -o yaml
kubectl get deployment api-gateway
~~~

No recrees los otros cinco microservicios. Si el Gateway no arranca, revisa referencias, eventos, logs y discovery antes de modificar la configuración. No desactives la seguridad para hacer pasar el ejercicio.

Terminal A (mantén activo el port-forward privado):

~~~bash
kubectl port-forward service/api-gateway 8080:8080
~~~

Terminal B:

~~~bash
curl -i 'http://127.0.0.1:8080/api/orders/preview?sku=SKU-001&quantity=2'
curl -i 'http://127.0.0.1:8080/actuator/health'
~~~

Registra 401 y 200 respectivamente. Si el port-forward se interrumpe al reemplazar un Pod, vuelve a abrirlo después del rollout. La salud del proceso no requiere una sesión de usuario.

## CORE 3 — Obtén y examina las identidades

Utiliza exclusivamente las cuentas Keycloak asignadas por el instructor. La identidad Entra que te permite operar AKS es distinta de la identidad de la aplicación.

~~~bash
bash labs/p05-api-security/scripts/device-login.sh reader
~~~

Abre el enlace de dispositivo en una ventana privada, inicia sesión como lector y autoriza la solicitud. No compartas el código. Cierra todas las ventanas privadas de esa sesión antes de solicitar el perfil admin:

~~~bash
bash labs/p05-api-security/scripts/device-login.sh admin
~~~

Los tokens se guardan en ~/.cache/advanced-orders, con permisos privados. No los muestres ni copies. El helper de peticiones lee el archivo en memoria y conecta únicamente con el port-forward local; no envía el token como argumento de shell ni sigue redirects.

Inspecciona únicamente los claims seleccionados:

~~~bash
python3 labs/p05-api-security/scripts/request.py reader --claims
python3 labs/p05-api-security/scripts/request.py admin --claims
~~~

Comprueba iss, aud, exp y roles. Un decode local **no valida la firma** ni demuestra que el token sea aceptable. Si ambos perfiles contienen roles privilegiados, revisa qué cuenta utilizaste; vuelve a iniciar el Device Grant en una nueva sesión privada.

## CORE 4 — Construye tu matriz de autorización

Elige y ejecuta las peticiones una a una. La sintaxis es:

~~~bash
python3 labs/p05-api-security/scripts/request.py PERFIL 'RUTA'
~~~

PERFIL puede ser none, invalid, reader o admin. El helper realiza una petición, muestra código HTTP y, cuando exista, Retry-After. Sustituye los marcadores por valores reales. Ejemplo de una prueba con un token deliberadamente inválido (no se modifica ningún token real):

~~~bash
python3 labs/p05-api-security/scripts/request.py invalid '/api/orders/preview?sku=SKU-001&quantity=2'
~~~

Completa tu matriz, utilizando las reglas Java y las rutas de P01:

| Perfil | Ruta | Predicción | HTTP observado | Regla que lo explica |
|---|---|---|---|---|
| none | Orders preview | | | |
| invalid | Orders preview | | | |
| reader | Orders preview | | | |
| reader | Payments methods | | | |
| admin | Payments methods | | | |
| reader | Shipping quote | | | |
| reader | Notifications provider | | | |
| admin | Notifications provider | | | |
| none | Actuator health | | | |

Usa las rutas completas y parámetros de P01. Distingue ausencia o invalidez de autenticación (401), falta de autorización de una identidad válida (403) y éxito (200). No cambies los roles compartidos para resolver una denegación esperada.

**Checkpoint:** elige una ruta adicional y prueba con ambos perfiles. Justifica el resultado a partir de la regla, no de una etiqueta PASS. El verificador final se ejecutará solo después de recuperar la configuración y retirar el rate limit de entrenamiento.

## CORE 5 — Diagnostica un fallo de audiencia

El proveedor no ha cambiado y las peticiones autenticadas funcionaban. Simula un error de integración del Resource Server: edita tu ConfigMap de trabajo y cambia únicamente OIDC_AUDIENCE a un identificador de recurso diferente, por ejemplo advanced-orders-wrong. No alteres el issuer, la cuenta, el JWT ni las reglas de autorización.

Antes de aplicar, predice el efecto sobre health, Orders con lector y Payments con administrador. Un ConfigMap consumido como variables de entorno requiere recrear los Pods para incorporar sus cambios.

~~~bash
kubectl apply -f work/p05/security-settings.yaml
kubectl rollout restart deployment/api-gateway
kubectl rollout status deployment/api-gateway --timeout=300s
~~~

Reabre el port-forward si es necesario y repite tres peticiones elegidas. Compara la audiencia que observaste en los claims con el ConfigMap y consulta logs:

~~~bash
kubectl get configmap p05-security-settings -o yaml
kubectl logs deployment/api-gateway --tail=60
~~~

Explica por qué un usuario con el rol correcto puede recibir 401 y por qué health puede seguir en 200. No supongas que se ha roto la firma. Si el token expiró durante el ejercicio, renueva el mismo perfil y repite.

**Recuperación:** restaura en tu fichero la audiencia correcta, aplica el ConfigMap y reinicia el Gateway. Repite la matriz mínima: anónimo Orders 401, lector Orders 200, lector Payments 403, administrador Payments 200. Conserva las evidencias antes/después. No utilices el helper de despliegue para ocultar el error.

## CORE 6 — Rate limiting por identidad autenticada

### Requisitos y alcance

El instructor debe confirmar la disponibilidad de la imagen adicional api-gateway:0.2.1-rate en el ACR del entorno. Si aún no está publicada, conserva el Gateway 0.2.0-sec protegido y no ejecutes este bloque hasta que el instructor lo indique.

El código de entrenamiento está en CourseRateLimiter.java y CourseRateLimitFilter.java. Implementa una ventana fija local a una instancia, con contador por subject del JWT autenticado. Solo limita GET /api/orders/preview, tras el filtro de seguridad. Devuelve HTTP 429 y Retry-After cuando se agota el presupuesto. No utiliza IP ni headers controlados por el cliente. El contador se reinicia por ventana y al recrear el Pod. No es una protección DDoS de perímetro, ni una cuota global distribuida, ni un token bucket.

### Configura el límite

Copia el manifiesto del Gateway seguro en tu carpeta de trabajo:

~~~bash
cp labs/p05-api-security/manifests/01-api-gateway-secure.yaml work/p05/gateway-rate.yaml
~~~

Modifica únicamente tu copia:
- cambia la etiqueta de imagen a 0.2.1-rate y la label de versión de la plantilla al mismo valor;
- conserva una réplica, el ConfigMap de OIDC y las probes;
- activa los perfiles p05-security,p05-rate-limit;
- añade las variables P05_RATE_LIMIT_REQUESTS y P05_RATE_LIMIT_WINDOW_SECONDS en env, con valores de cadena YAML. Empieza con 3 peticiones por ventana de 10 segundos.

Predice qué sucede con una ráfaga de 8 peticiones de un lector. ¿El contador se comparte con un administrador? ¿Qué pasa al cruzar el límite de una ventana?

~~~bash
kubectl apply --dry-run=server -f work/p05/gateway-rate.yaml
kubectl apply -f work/p05/gateway-rate.yaml
kubectl rollout status deployment/api-gateway --timeout=300s
~~~

Si el port-forward termina, vuelve a abrirlo. Verifica primero que la seguridad sigue funcionando (none 401, reader Payments 403, admin Payments 200, health 200). Renueva tokens si es necesario.

### Experimenta y ajusta

Ejecuta una ráfaga acotada contra tu propio Gateway. No generes carga fuera de este namespace.

~~~bash
python3 labs/p05-api-security/scripts/request.py reader '/api/orders/preview?sku=SKU-001&quantity=2' --repeat 8
~~~

Registra los códigos y Retry-After de las respuestas 429. En una ventana fija pueden existir más éxitos de lo previsto si el experimento cruza un límite de ventana; no presupongas una distribución exacta. Repite tras recuperar el presupuesto si la primera ráfaga no permite observar 429. Si el tráfico sigue sin alcanzar el límite, reduce el presupuesto a 1 mediante tu configuración y repite. No aumentes el número de peticiones indiscriminadamente.

Comprueba con el perfil admin si dispone de un presupuesto independiente; haz la prueba dentro de la misma ventana si es posible. Después de Retry-After, verifica que el lector puede acceder de nuevo. Confirma que una ruta autorizada distinta y health no consumen la cuota de Orders.

**Tu decisión:** cambia la configuración a 2 peticiones por ventana de 15 segundos y repite el experimento. Explica por qué no basta con modificar un archivo local: debes aplicar el Deployment, esperar el rollout y reabrir el túnel. Compara ambas políticas e indica qué efectos podría tener una cuota demasiado estricta.

### Límites y cierre de rate limiting

El filtro solo cubre el Gateway y la ruta configurada. Dos réplicas tendrían contadores independientes y un reinicio perdería el estado. En producción compara con un token bucket distribuido, Redis con operación atómica o un gateway gestionado; define qué harías si el almacén de cuotas falla. No afirmes que una ventana fija evita ráfagas en su frontera.

**Restaura el Gateway seguro original antes de P06/P07.** Reaplica el manifiesto 01-api-gateway-secure.yaml y elimina explícitamente las variables de rate limit que añadiste. Comprueba el perfil, imagen y rollout. No borres el ConfigMap de OIDC ni desactives el Resource Server.

~~~bash
kubectl apply -f labs/p05-api-security/manifests/01-api-gateway-secure.yaml
kubectl set env deployment/api-gateway P05_RATE_LIMIT_REQUESTS- P05_RATE_LIMIT_WINDOW_SECONDS-
kubectl rollout status deployment/api-gateway --timeout=300s
kubectl get deployment api-gateway -o json | jq '.spec.template.spec.containers[] | {image,env}'
~~~

Reabre el port-forward y confirma el resultado con la matriz de autorización.

## CORE 7 — Reto de transferencia: el bypass del Gateway

El equipo afirma que todas las operaciones de Orders están protegidas porque una petición anónima al Gateway devuelve 401. Diseña una comprobación de esa afirmación desde un Pod de tu namespace, usando los comandos de diagnóstico de P01. No publiques un Service ni cambies NetworkPolicy, RBAC o Istio.

Pista: el contenedor Gateway dispone de curl y los Services internos conservan sus nombres DNS. Compara la respuesta al Gateway sin JWT con la respuesta directa a Orders por su Service, también sin JWT. Selecciona tú la ruta y registra ambas respuestas.

¿La autorización del Gateway protege todas las comunicaciones entre workloads? ¿Una política mTLS equivale a autorización por usuario? ¿Qué controles adicionales requerirías para impedir el bypass? No implementes cambios que bloqueen las prácticas siguientes.

## Evidencia y cierre

Con la versión 0.2.0-sec y el perfil p05-security restaurados:

~~~bash
bash labs/p05-api-security/scripts/verify.sh
~~~

Entrega:
- ConfigMap y manifiesto de rate limit de trabajo, sin credenciales.
- Claims seleccionados sin JWT, matriz HTTP y explicación de las reglas.
- Evidencia de audiencia incorrecta y recuperación.
- Resultados 200/429, Retry-After y comparación de políticas.
- Evidencia del bypass y propuesta de controles.

El verificador comprueba el estado final de seguridad, no sustituye los experimentos. Conserva los tokens privados y el Gateway protegido para P06/P07. No ejecutes cleanup salvo indicación del instructor.

## SUPPORT

- 401 inesperado: revisa expiración, issuer y audiencia; renueva el perfil correcto.
- 403 inesperado: comprueba roles y ruta, no modifiques el realm.
- 429 inesperado: revisa perfil activo, configuración y ventana.
- Rollout bloqueado: consulta describe, eventos y logs; confirma imagen y ConfigMap.
- Port-forward desconectado: espera al Pod Ready y vuelve a abrir el túnel privado.
- Si el instructor indica recuperación de P05, usa scripts/deploy.sh para restaurar el Gateway seguro con los identificadores del entorno. scripts/cleanup.sh vuelve al Gateway sin autenticación de P01: no lo uses como solución a un 401.

Nunca compartas tokens, device codes, contraseñas ni kubeconfigs.
