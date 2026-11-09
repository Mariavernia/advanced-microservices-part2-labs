# P01 — Advanced Orders Platform sobre Kubernetes

**Modo:** individual. **Punto de partida:** P00.
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

## 1. Del baseline a seis servicios
Asegúrate de tener el contexto correcto:

```bash
./scripts/preflight.sh
kubectl config view --minify -o jsonpath='{..namespace}'; echo
```

Despliega los recursos del laboratorio:

```bash
bash labs/p01-complete-platform/scripts/deploy.sh
kubectl get deployments,pods,services
kubectl get configmap
```

**Checkpoint:** seis Deployments y seis Services. Si aparecen errores, investiga
`kubectl describe pod ...` y `kubectl get events --sort-by=.lastTimestamp`.
No cambies URLs de imagen para resolver un problema de permisos de ACR.

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

Edita `orders-config` y sustituye `INVENTORY_BASE_URL` por
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

Repite la llamada y observa HTTP, logs y estado del Pod.
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

## Limpieza

```bash
bash labs/p01-complete-platform/scripts/cleanup.sh
```

**Atención:** también elimina Orders e Inventory del namespace, compartidos con P00.
