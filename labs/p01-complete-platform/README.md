# P01 — Advanced Orders Platform sobre Kubernetes

**Modo:** individual, guiado y manipulando recursos. **Punto de partida:** P00. Sigue [la metodología de prácticas](../../docs/METODOLOGIA-PRACTICAS.md).
Este laboratorio no es un curso de Spring: el código ya está desarrollado para que investigues
cómo se ejecuta y comunica una plataforma distribuida.

## Escenario

El equipo debe ampliar Orders + Inventory con un punto de entrada y tres capacidades
adicionales. Necesitamos **API Gateway, Orders, Inventory, Payments, Shipping y Notifications**,
desplegados de manera independiente en tu namespace de AKS.

El funcionamiento de Payments, Shipping y Notifications es deliberadamente **simulado**:
en P01 no se realiza ningún cobro, contratación real de transporte ni envío de mensajes.
El servicio Query/Projection no se crea todavía; tendrá sentido cuando introduzcamos
persistencia y caché en P04.

```text
             API Gateway
              /  |  \
         Orders Payments Shipping -- (rutas independientes)
            |     Notifications (otra ruta)
         Inventory
```

La representación es lógica: el Gateway enruta también directamente a Inventory,
Payments, Shipping y Notifications. Orders consulta Inventory de forma síncrona.

## Objetivos CORE

- Desplegar e inspeccionar seis Deployments y sus Services.
- Explicar qué parte del tráfico resuelve el Gateway y qué parte un Kubernetes Service.
- Localizar configuración no confidencial en ConfigMaps y una credencial ficticia en Secret.
- Distinguir `requests` y `limits` sin confundirlos con consumo real.
- Diagnosticar un fallo por configuración incorrecta con evidencia, repararlo y verificar.
- Explicar qué capacidades nos siguen faltando para operar el sistema de manera robusta.

## 0. Predicción antes del despliegue
Abre `manifests/00-configmaps.yaml` y los manifiestos de Orders y API Gateway.

Responde antes de aplicar: ¿qué destino utilizará Orders para contactar Inventory?,
¿qué destinos conoce el Gateway?, ¿qué pasa si un Service tiene cero endpoints?,
¿en qué archivos aparecen `requests` y `limits`?

## 1. Del baseline a seis servicios: construye la plataforma paso a paso

**Esta es la ruta del alumno:** aplica recursos individuales, inspecciona cada cambio y explica qué has construido. **No ejecutes `scripts/deploy.sh`**: ese script queda disponible para el instructor o la recuperación de un entorno bloqueado.

Asegúrate de tener el contexto correcto:

```bash
./scripts/preflight.sh
kubectl config view --minify -o jsonpath='{..namespace}'; echo
kubectl get deployment,service
```

### 1A. Configuración: descubre los destinos

Abre `manifests/00-configmaps.yaml`. Identifica el destino usado por Orders y los cinco destinos configurados para el Gateway. ¿Qué nombres corresponden a **Services** de Kubernetes? ¿Qué ocurriría si uno no tuviera endpoints?

```bash
kubectl apply -f labs/p01-complete-platform/manifests/00-configmaps.yaml
kubectl get configmap orders-config gateway-routing -o yaml
```

### 1B. Inventario y pedidos: reutiliza el punto de partida de P00

Abre `manifests/01-inventory.yaml` y `02-orders.yaml`. Cada archivo contiene **un Deployment y un Service**. Localiza selectors, labels, imagen, `envFrom`, `requests` y `limits`.

```bash
kubectl apply -f labs/p01-complete-platform/manifests/01-inventory.yaml
kubectl apply -f labs/p01-complete-platform/manifests/02-orders.yaml
kubectl rollout status deployment/inventory --timeout=240s
kubectl rollout status deployment/orders --timeout=240s
kubectl get deployments,services,endpointslices
```

**Checkpoint:** ¿qué recursos han sido *created*, *configured* o *unchanged* al venir de P00? ¿Por qué el Service de Inventory resuelve los Pods correctos?

### 1C. Añade capacidades de negocio una por una

Primero inspecciona `03-payments.yaml` y `04-shipping.yaml`. Predice cuántos objetos Kubernetes creará cada archivo y compruébalo después:

```bash
kubectl apply -f labs/p01-complete-platform/manifests/03-payments.yaml
kubectl rollout status deployment/payments --timeout=240s
kubectl get svc payments
kubectl get endpointslice -l kubernetes.io/service-name=payments

kubectl apply -f labs/p01-complete-platform/manifests/04-shipping.yaml
kubectl rollout status deployment/shipping --timeout=240s
kubectl get svc shipping
```

**Tarea de edición real del manifiesto (sin script):** abre `04-shipping.yaml` en tu fork, cambia **solo** `resources.limits.cpu` del contenedor Shipping de `400m` a `250m` y guarda. Antes de aplicar, explica qué diferencia hay entre ese límite y el `request.cpu=50m`.

```bash
git diff -- labs/p01-complete-platform/manifests/04-shipping.yaml
kubectl apply -f labs/p01-complete-platform/manifests/04-shipping.yaml
kubectl rollout status deployment/shipping --timeout=240s
kubectl describe pod -l app.kubernetes.io/name=shipping
```

Comprueba que el Pod nuevo refleja el límite. **Restaura `400m` en el archivo**, vuelve a aplicar el manifiesto y verifica que el sistema termina en el estado original. No modifiques la imagen ni las cuotas del namespace.

Antes de desplegar Notifications, busca `secretKeyRef` en `05-notifications.yaml`. ¿Por qué no debería aparecer aquí un token real? El siguiente **helper de preparación** crea una credencial aleatoria *ficticia* sin imprimirla; generar tokens no es el objetivo de P01:

```bash
bash labs/p01-complete-platform/scripts/prepare-demo-secret.sh
kubectl apply -f labs/p01-complete-platform/manifests/05-notifications.yaml
kubectl rollout status deployment/notifications --timeout=240s
kubectl describe deployment notifications
```

**Checkpoint:** relaciona el nombre del Secret con la referencia del Deployment, sin mostrar el valor del token.

### 1D. El Gateway es el último componente

Antes de aplicarlo, abre `manifests/06-api-gateway.yaml` y contesta: ¿dónde obtiene las URL de los destinos? ¿Podría un Gateway estar Ready aunque uno de sus backends devolviera 5xx?

```bash
kubectl apply -f labs/p01-complete-platform/manifests/06-api-gateway.yaml
kubectl rollout status deployment/api-gateway --timeout=240s
kubectl get deployments,pods,services
```

**Checkpoint final de despliegue:** seis Deployments y seis Services; para cada Service identifica el selector y al menos un endpoint. Si hay errores, empieza por `kubectl describe pod`, eventos y logs; no cambies las imágenes ni los permisos de ACR.

## 2. Recorre el sistema
Terminal 1:

```bash
kubectl port-forward service/api-gateway 8080:8080
```

Terminal 2:

```bash
curl -sS 'http://localhost:8080/api/orders/preview?sku=SKU-001&quantity=2' | jq
curl -sS 'http://localhost:8080/api/payments/methods' | jq
curl -sS 'http://localhost:8080/api/shipping/quote?destination=ES&weightGrams=500' | jq
curl -sS 'http://localhost:8080/api/notifications/provider' | jq
```

Traza mentalmente el recorrido **Gateway → Orders → Inventory**.
¿Cuáles de las llamadas del Gateway se resuelven sin pasar por Orders?

## 3. El fallo de configuración que no se manifiesta inmediatamente
Consulta la configuración y los endpoints:

```bash
kubectl get configmap orders-config -o yaml
kubectl get endpointslice -l kubernetes.io/service-name=inventory
kubectl logs deployment/orders --tail=20
```

**Tu tarea es introducir el fallo manualmente, no ejecutar un script que lo provoque.** Edita `orders-config` y sustituye `INVENTORY_BASE_URL` por
`http://inventory-incorrect:8080`:

```bash
kubectl edit configmap orders-config
```

Repite el preview. ¿Cambió? ¿Por qué?

Ahora recrea las instancias gestionadas por el Deployment:

```bash
kubectl rollout restart deployment/orders
kubectl rollout status deployment/orders
```

Repite la llamada y observa el código HTTP **real** (en una prueba de preparación se observó 500 genérico), logs y estado del Pod. No presupongas que el error será 502.
Construye una hipótesis basada en evidencia: ¿falta un Service?, ¿falta un endpoint?,
¿o Orders intenta contactar con el nombre incorrecto?

**Repara** la configuración: restaura la URL válida editando el ConfigMap o
reaplicando `manifests/00-configmaps.yaml`; después reinicia Orders de forma
controlada y demuestra que el preview vuelve a funcionar.

## 4. Secret + requests/limits
Inspecciona cómo Notifications consume el Secret `notifications-provider`:

```bash
kubectl describe deployment notifications
kubectl get secret notifications-provider
kubectl get deployment notifications -o yaml
```

Comprueba que el endpoint `/api/notifications/provider` comunica únicamente
`credentialConfigured`, sin mostrar el token. La credencial es **sintética**
y no corresponde a proveedor real alguno. En Git nunca se incluyen secretos
auténticos. La codificación base64 no proporciona cifrado.

Compara los `requests` y `limits` de Orders y Payments:
¿puede un Pod estar `Running` y la API no funcionar? ¿Qué ocurriría ante OOM?
¿Por qué dejamos las probes para P02?

## 5. Diagnóstico de transferencia
Reproduce o recibe del instructor una ruta con fallo 5xx, aunque tanto el Gateway
como el Service del destino existan. Sin comenzar por reinicios indiscriminados:

1. Formula dos hipótesis posibles.
2. Obtén evidencia con logs, ConfigMap, Service y EndpointSlice.
3. Elige la hipótesis mejor respaldada y explica por qué.
4. Aplica una corrección.
5. Demuestra el comportamiento reparado mediante HTTP.

**STRETCH:** repite el diagnóstico con una ruta distinta y sin indicación previa
de qué configuración se ha alterado. Propón una verificación preventiva.

## 6. Verificación y debrief
```bash
bash labs/p01-complete-platform/scripts/verify.sh
```

**Solo ahora** utiliza `verify.sh`. No sirve para desplegar la plataforma ni para corregir el incidente. Entrega cuatro frases: *predije, cambié, observé, concluyo* y al menos una evidencia de EndpointSlice, logs o HTTP.

No es suficiente conseguir PASS. Justifica el resultado y compara:

| Antes (P00) | Después (P01) |
|---|---|
| Dos servicios | Seis workloads |
| Sin punto de entrada de aplicación | API Gateway |
| URL de Inventory embebida en Deployment | ConfigMap |
| Sin recurso de credenciales | Secret sintético para Notifications |
| Recursos sin requests/limits explícitos | Requests/limits para cada contenedor |
| Diagnóstico elemental | Incidente de configuración reproducible |

### Debrief

- ¿Por qué el cambio del ConfigMap no se reflejó hasta reiniciar Orders?
- ¿Qué diferencia hay entre el API Gateway y un Kubernetes Service?
- ¿Qué faltaría para que el Secret fuese una solución productiva de gestión de credenciales?
- ¿Qué demuestra `Ready`, y qué no podemos concluir todavía sin probes?
- ¿Qué riesgos introduce tener varios servicios con una única réplica?

## SUPPORT

```bash
kubectl get deployments,pods,services
kubectl describe pod POD_NAME
kubectl logs deployment/orders
kubectl get endpointslice -l kubernetes.io/service-name=inventory
kubectl get configmap orders-config -o yaml
kubectl exec deploy/api-gateway -- curl -sS http://orders:8080/actuator/health
```

Si `./scripts/preflight.sh` falla, eso es un bloqueo de entorno, no una tarea
de diagnóstico de los manifiestos.

## Recuperación excepcional del entorno

Si el ejercicio queda inutilizable tras una manipulación, el instructor puede usar `bash labs/p01-complete-platform/scripts/deploy.sh` para recuperar la plataforma. **No es un paso del recorrido del alumno:** evita saltarse la construcción y el diagnóstico.

## Limpieza

```bash
bash labs/p01-complete-platform/scripts/cleanup.sh
```

**Atención:** también elimina Orders e Inventory del namespace, compartidos con P00.
