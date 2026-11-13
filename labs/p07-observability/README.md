# P07 — Investigar un incidente distribuido con métricas, trazas y logs

> **Modalidad:** Codespaces en fork + AKS; sin instalaciones locales.  
> **Predecesores:** P01–P06.

## Incidente

Una petición a `Orders` tarda demasiado o falla porque `Inventory` introduce latencia. El alumno debe contestar con pruebas:

1. ¿El usuario percibe error o latencia? ¿En qué endpoint?
2. ¿Qué microservicio es responsable? ¿Cómo separas dependencia/infraestructura?
3. ¿Qué señal aportan métricas, logs y **trazas distribuidas reales**?
4. ¿Cómo verificas recuperación y diferencia entre síntoma y causa?

Se utiliza **Jaeger temporal y privado en el namespace de cada alumno**, con almacenamiento en memoria y acceso por port-forward privado. Así evitamos compartir trazas entre participantes.

## Recorrido CORE

**CORE 1 — Señal:** reproducir la respuesta de la API y medir duración/tasa de error. Registrar qué puede observarse solo con `curl`.

**CORE 2 — Métrica:** inspeccionar métricas de servicio y Kubernetes ya desplegadas, distinguir CPU/memoria de duración HTTP; correlacionar temporalmente con el fallo.

**CORE 3 — Traza:** identificar un `trace_id` que conecte Gateway → Orders → Inventory y localizar el span lento. Para comparar latencias, utilizar Orders → Inventory directamente; la petición autenticada completa constituye una comprobación adicional.

**CORE 4 — Logs:** filtrar logs de la petición/trace_id sin publicar secretos ni JWT. Diferenciar log local de correlación distribuida.

**CORE 5 — Recuperación:** revertir el fallo inducido, comprobar que mejoran las señales y redactar RCA de 5 líneas con evidencias.

## Preparación 1 — Backend de trazas

El manifiesto `manifests/01-jaeger-pilot.yaml` crea Jaeger 2.23.0 en el namespace actual, con un Deployment y un Service ClusterIP, sin PVC ni exposición pública. Solo requiere el RBAC ya concedido para Deployments/Services. Se fijan 100m/192Mi de requests y 500m/512Mi de límites; validar consumo real. No representa todavía trazas de la aplicación.

```bash
kubectl apply --dry-run=server -f labs/p07-observability/manifests/01-jaeger-pilot.yaml
kubectl apply -f labs/p07-observability/manifests/01-jaeger-pilot.yaml
kubectl rollout status deployment/p07-jaeger --timeout=180s
kubectl get deployment,service p07-jaeger
kubectl get pods -l app.kubernetes.io/name=p07-jaeger
kubectl port-forward service/p07-jaeger 16686:16686
```

Abrir la UI mediante el puerto privado de Codespaces. El endpoint `/api/v3/services` debe responder; no se espera que aparezcan Orders/Inventory hasta instrumentarlos. Cleanup: `kubectl delete -f labs/p07-observability/manifests/01-jaeger-pilot.yaml`. Jaeger utiliza almacenamiento efímero: se pierden las trazas cuando se recrea el Pod.

La cuota se consulta desde Cloud Shell administrativa: el rol de alumno no autoriza leer ResourceQuota. No es necesario modificar RBAC.

## Preparación 2 — Instrumentación Java

```bash
bash labs/p07-observability/scripts/instrument.sh backend
# Solo si pasa el preflight:
CONFIRM_P07_INSTRUMENT=YES bash labs/p07-observability/scripts/instrument.sh backend

# Validar primero una traza real Orders → Inventory; después, en otra fase:
bash labs/p07-observability/scripts/instrument.sh gateway
CONFIRM_P07_INSTRUMENT=YES bash labs/p07-observability/scripts/instrument.sh gateway
```

El helper añade el agente oficial OpenTelemetry Java 2.30.0 mediante initContainer y emptyDir, configura JAVA_TOOL_OPTIONS, nombres de servicio y OTLP HTTP/protobuf hacia Jaeger dentro del mismo namespace. Conserva imágenes y variables existentes de P05 y etiquetas P06. Ajusta memoria de las aplicaciones instrumentadas a 256Mi request y 768Mi limit para el laboratorio. Añade startupProbe (hasta 300 s antes de habilitar liveness) y readinessProbe HTTP; se conservan las sondas liveness existentes. Si falla un rollout, recoge estados y logs de la revisión fallida antes de intentar recuperar las revisiones originales de esa fase. El fallo de Gateway no revierte Orders e Inventory ya instrumentados en la fase backend. Comprueba que aparecen los servicios Orders e Inventory y, después, Gateway en una petición autenticada. Las métricas y logs OTLP están deshabilitados en esta fase, porque Jaeger es backend de trazas. 

## Alcance de la instrumentación

El recorrido CORE abarca Gateway, Orders e Inventory. Las métricas se consultan mediante Actuator y los logs mediante kubectl; Jaeger almacena las trazas. Mantén todos los recursos de observabilidad dentro de tu namespace y los port-forwards privados.

## STRETCH (opcional)

Comparar cardinalidad de métricas, retención, sampling y costes; analizar una traza con múltiples dependencias; construir una alerta basada en error budget.

## Preparación 3 — Incidente de latencia

Inventory añade una propiedad de entrenamiento `training.inventory.delay-ms` (variable `TRAINING_INVENTORY_DELAY_MS`), con valor por defecto 0 y máximo efectivo de 3000 ms. La latencia se introduce en el controlador para que aparezca dentro del span receptor y se registra con un warning; no afecta a las sondas Actuator. No aplicar a imágenes P01–P06 ni publicar un tag existente.

La imagen `advancedorders/inventory:0.1.0-p07` está publicada en el registro del entorno. Actualiza solo Inventory en tu namespace, preservando los sidecars y el agente. Habilita Actuator metrics para observar `http.server.requests` y correlaciona los logs mediante trace_id/span_id. Compara la línea base con una latencia de 1500 ms y restaura el valor 0 al terminar.

## Ejecución del incidente — alumno

Prerequisitos: P01–P06; Jaeger y las dos fases de instrumentación anteriores funcionando; namespace propio y ninguna PeerAuthentication STRICT activa. Todos los comandos siguientes se ejecutan en Codespaces, nunca con la identidad administrativa. Completa la activación selectiva de P06 antes de empezar. No ejecutes su limpieza de mTLS más allá de retirar STRICT; conserva los sidecars.

### CORE 1 — Línea base

Actualizar solo Inventory. Conservar recursos, agente, labels de Istio y sondas:

```bash
kubectl patch deployment inventory --type=strategic -p "$(jq -nc '{
  spec:{template:{spec:{containers:[{
    name:"inventory",
    image:"advms26acr4366001b.azurecr.io/advancedorders/inventory:0.1.0-p07",
    env:[
      {name:"TRAINING_INVENTORY_DELAY_MS",value:"0"},
      {name:"MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE",value:"health,info,metrics"},
      {name:"LOGGING_PATTERN_CONSOLE",value:"%d{HH:mm:ss.SSS} level=%-5level trace_id=%X{trace_id:-none} span_id=%X{span_id:-none} logger=%logger{36} msg=%msg%n"}
    ]
  }]}}}
}')"
kubectl rollout status deployment/inventory --timeout=420s

p07_request() {
  TRACE_ID=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
  SPAN_ID=$(python3 -c 'import secrets; print(secrets.token_hex(8))')
  kubectl exec deploy/orders -c orders -- curl -sS --max-time 20 \
    -H "traceparent: 00-${TRACE_ID}-${SPAN_ID}-01" \
    -w '\nHTTP %{http_code} | Tiempo: %{time_total}s\n' \
    'http://127.0.0.1:8080/api/orders/preview?sku=SKU-001&quantity=2'
  echo "Trace ID: $TRACE_ID"
}
p07_metrics() {
  kubectl exec deploy/inventory -c inventory -- curl -fsS -G \
    'http://127.0.0.1:8080/actuator/metrics/http.server.requests' \
    --data-urlencode 'tag=uri:/api/inventory/{sku}' |
    jq '{name,baseUnit,measurements}'
}

p07_request
p07_request
p07_request
p07_metrics
BASELINE_TRACE_ID="$TRACE_ID"
```

Anota el código, el tiempo, COUNT/TOTAL_TIME/MAX y el identificador de la última traza. Busca el identificador en Jaeger (port-forward privado a 16686). El span de Inventory debe aparecer dentro de la traza de Orders. Si aparece Incomplete, el padre externo generado para traceparent no tiene span exportado: comprueba que los spans de aplicación sí están presentes.

### CORE 2–4 — Introducir latencia, medir y localizar el origen

```bash
kubectl set env deployment/inventory TRAINING_INVENTORY_DELAY_MS=1500
kubectl rollout status deployment/inventory --timeout=420s
p07_request
p07_request
p07_request
INCIDENT_TRACE_ID="$TRACE_ID"
p07_metrics
kubectl logs deployment/inventory -c inventory --tail=100 | grep 'P07 simulated'
kubectl logs deployment/inventory -c inventory --tail=100 | grep "$INCIDENT_TRACE_ID"
```

Busca INCIDENT_TRACE_ID en Jaeger. Compara la duración de Inventory con la línea base y con el span cliente de Orders. ¿Qué evidencia permite descartar que el retraso se produzca únicamente en la red? Calcula TOTAL_TIME / COUNT. Las métricas se reinician con cada recreación de Inventory, de modo que las fases son muestras distintas; no restes contadores. Conserva el ID de incidente antes de pasar a recuperación.

### CORE 5 — Recuperación y RCA

Ejecuta incluso si falla una comprobación anterior:

```bash
kubectl set env deployment/inventory TRAINING_INVENTORY_DELAY_MS=0
kubectl rollout status deployment/inventory --timeout=420s
p07_request
p07_request
p07_request
RECOVERY_TRACE_ID="$TRACE_ID"
p07_metrics
```

Entrega un RCA breve: síntoma, alcance, causa, evidencias (métrica, traza, log) y recuperación. Las tres fases deben mantener el contrato de negocio HTTP 200 y canBeFulfilled=true en el ensayo normal; si alguna falla, registra el resultado real y recupera igualmente la configuración. La limpieza del backend de trazas y de la instrumentación se hará conforme al plan de fin de laboratorio; no borres Jaeger hasta guardar las evidencias.

## Evidencia mínima

- Registra HTTP, latencia de cliente y las medidas COUNT, TOTAL_TIME y MAX en las tres fases.
- Identifica el span lento y correlaciona un log con el mismo trace_id; distingue el tiempo de servidor de Inventory del tiempo observado por Orders.
- Comprueba que la latencia vuelve a la línea base tras restaurar el valor 0 y que el contrato de negocio se mantiene.
- Guarda tus propias evidencias antes de retirar Jaeger; su almacenamiento en memoria es efímero.
