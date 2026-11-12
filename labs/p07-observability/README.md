# P07 — Investigar un incidente distribuido con métricas, trazas y logs

> **Estado: P07 CORE PASS desde Codespaces student02 (12/11/2026): Jaeger, traza distribuida autenticada, incidente, métricas, logs correlacionados, traza degradada y recuperación. Pendientes: dimensionamiento y entrega de cohorte.**  
> **Modalidad:** Codespaces en fork + AKS; sin instalaciones locales.  
> **Predecesores:** P01–P06.

## Incidente

Una petición a `Orders` tarda demasiado o falla porque `Inventory` introduce latencia. El alumno debe contestar con pruebas:

1. ¿El usuario percibe error o latencia? ¿En qué endpoint?
2. ¿Qué microservicio es responsable? ¿Cómo separas dependencia/infraestructura?
3. ¿Qué señal aportan métricas, logs y **trazas distribuidas reales**?
4. ¿Cómo verificas recuperación y diferencia entre síntoma y causa?

Se utiliza **Jaeger temporal y privado en el namespace de cada alumno**, con almacenamiento en memoria y acceso por port-forward privado. Así evitamos compartir trazas entre participantes. Este diseño está validado en student02; queda el ensayo de capacidad concurrente.

## Recorrido CORE

**CORE 1 — Señal:** reproducir la respuesta de la API y medir duración/tasa de error. Registrar qué puede observarse solo con `curl`.

**CORE 2 — Métrica:** inspeccionar métricas de servicio y Kubernetes ya desplegadas, distinguir CPU/memoria de duración HTTP; correlacionar temporalmente con el fallo.

**CORE 3 — Traza:** identificar un `trace_id` que conecte Gateway → Orders → Inventory y localizar el span lento. Para comparar latencias, utilizar Orders → Inventory directamente; la petición autenticada completa constituye una comprobación adicional.

**CORE 4 — Logs:** filtrar logs de la petición/trace_id sin publicar secretos ni JWT. Diferenciar log local de correlación distribuida.

**CORE 5 — Recuperación:** revertir el fallo inducido, comprobar que mejoran las señales y redactar RCA de 5 líneas con evidencias.

## Piloto 0 — backend de trazas (validado)

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

## Piloto 1 — instrumentación Java (validada)

```bash
bash labs/p07-observability/scripts/instrument.sh backend
# Solo si pasa el preflight:
CONFIRM_P07_INSTRUMENT=YES bash labs/p07-observability/scripts/instrument.sh backend

# Validar primero una traza real Orders → Inventory; después, en otra fase:
bash labs/p07-observability/scripts/instrument.sh gateway
CONFIRM_P07_INSTRUMENT=YES bash labs/p07-observability/scripts/instrument.sh gateway
```

El helper añade el agente oficial OpenTelemetry Java 2.30.0 mediante initContainer y emptyDir, configura JAVA_TOOL_OPTIONS, nombres de servicio y OTLP HTTP/protobuf hacia Jaeger dentro del mismo namespace. Conserva imágenes y variables existentes de P05 y etiquetas P06. Ajusta memoria de las aplicaciones instrumentadas a 256Mi request y 768Mi limit para el piloto. Añade startupProbe (hasta 300 s antes de habilitar liveness) y readinessProbe HTTP; se conservan las sondas liveness existentes. Si falla un rollout, recoge estados y logs de la revisión fallida antes de intentar recuperar las revisiones originales de esa fase. El fallo de Gateway no revierte Orders e Inventory ya instrumentados en la fase backend. Validación real: una traza de negocio Orders → Inventory con 3 spans (10,7 ms total, 6,4 ms cliente HTTP, 2,6 ms servidor Inventory). Gateway instrumentado y traza autenticada completa confirmada: 3 servicios, 7 spans. Las métricas y logs OTLP están deshabilitados en esta fase, porque Jaeger es backend de trazas. 

## Preparación de cohorte (instructor)

- Medir capacidad antes de instalar collector, backend de trazas, Prometheus o Grafana.
- La instrumentación CORE abarca tres servicios: Gateway, Orders e Inventory; no presupone instrumentación de los otros tres.
- El incidente reversible mediante TRAINING_INVENTORY_DELAY_MS está validado en student02; mantenerlo aislado por namespace.
- Verificar RBAC de lectura y acceso a dashboards; no exponer dashboards públicos sin autenticación.
- Preparar la configuración reproducible para los 16 namespaces y realizar un ensayo de concurrencia.

## STRETCH (opcional)

Comparar cardinalidad de métricas, retención, sampling y costes; analizar una traza con múltiples dependencias; construir una alerta basada en error budget.

> El recorrido funcional se ha ensayado en student02. La disponibilidad simultánea para toda la cohorte todavía debe comprobarse.

## 12/11/2026 — Evidencia del piloto

- Jaeger 2.23.0, API v3, backend privado en student02. Exportación real de inventory/orders.
- Primer ensayo de Gateway: liveness reiniciaba el proceso antes de escuchar en 8080; la instrumentación se separó en backend y gateway, añadió startup/readiness probes y diagnóstico previo a rollback.
- Rollouts corregidos: Inventory y Orders 2/2 con proxy nativo, Gateway 1/1 sin sidecar, todos instrumentados y sin reinicios nuevos. Cinco previews HTTP 200 con canBeFulfilled=true.
- Captura Jaeger: trace ID `1f5c1b1659d115ab6de79f48ab8621bd`, 2 servicios, 3 spans, 10.7 ms total. Orders client 6.4 ms, Inventory server 2.6 ms.
- No confundir el arranque saludable del Gateway con validación de autenticación ni con prueba de la traza completa.

## Piloto 2 — Incidente de latencia (validado)

Inventory añade una propiedad de entrenamiento `training.inventory.delay-ms` (variable `TRAINING_INVENTORY_DELAY_MS`), con valor por defecto 0 y máximo efectivo de 3000 ms. La latencia se introduce en el controlador para que aparezca dentro del span receptor y se registra con un warning; no afecta a las sondas Actuator. No aplicar a imágenes P01–P06 ni publicar un tag existente.

El instructor ha construido el nuevo tag `advancedorders/inventory:0.1.0-p07` en ACR desde esta rama. Luego se cambiará solamente la imagen del Deployment Inventory en el namespace piloto, preservando sus sidecars y su agente. Se habilitará el endpoint interno Actuator metrics para observar `http.server.requests` y se añadirá trace_id/span_id al patrón de logs. Primero validar delay=0; después comparar con delay=1500 y restaurar 0. Los comandos operativos y las evidencias reales se incluyen a continuación.

### Evidencia 12/11/2026 — traza completa y build

- Captura Jaeger de una petición autenticada: 3 servicios, 7 spans, profundidad 5, HTTP 200. Gateway 5.8 s, Orders 16.3 ms, Inventory 2.3 ms. Primer span HTTP saliente de Gateway 3.8 s: identificar destino mediante atributos, no asumir que es Keycloak. Aviso Incomplete compatible con padre externo generado manualmente mediante traceparent.
- ACR run ca9 exitoso, tag `advancedorders/inventory:0.1.0-p07`, digest `sha256:bce6c3d8de426cd9846808540557fc4fc23002a030b415c3cabf47380649ec6a`. Maven compiló y empaquetó; tests omitidos por Dockerfile. El incidente se ha ejecutado y recuperado correctamente.

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

### Evidencia del ensayo student02, 12/11/2026

- Baseline: HTTP 200 en 3/3; tiempos cliente 40.350/11.217/59.174 ms. Inventory COUNT=3, TOTAL_TIME=0.01265115 s, MAX=0.0093016 s.
- Incidente: HTTP 200 en 3/3; tiempos cliente 1538.945/1512.111/1511.735 ms. Inventory COUNT=3, TOTAL_TIME=4.515659089 s, MAX=1.511112482 s.
- Recuperación: HTTP 200 en 3/3; tiempos cliente 28.149/11.127/10.825 ms, canBeFulfilled=true en todas las fases. Delay final=0.
- Traza normal f63858bc8f0dafdf4f3a8d0f62505c4e: captura de Jaeger 58.2 ms, Orders cliente 6.8 ms, Inventory 3.0 ms, 2 servicios / 3 spans.
- Traza de incidente d033cd9732cf138c64167196f9656ff8: logs WARN a 06:51:21.313Z y INFO a 06:51:22.813Z comparten trace_id y span_id c6f70027b487028c, confirmando el retraso de 1500 ms en el controlador. Captura Jaeger confirmada: duración total aproximada 1.5 s, 2 servicios, 3 spans, profundidad 3, HTTP 200 en los tres spans. El span servidor Inventory ocupa casi toda la duración de la traza, coherente con la latencia configurada y los logs. No se ha leído la duración exacta del span en sus atributos.
- Jaeger conserva trazas en memoria hasta que se recrea su Pod. No es necesario repetir el incidente para recuperar la evidencia si el backend sigue activo.

**Aceptación P07 CORE:** PASS real. La captura de la traza de incidente confirma la identificación de la dependencia lenta; la correlación por trace_id y la recuperación ya se verificaron. El aviso Incomplete es compatible con el padre externo artificial del traceparent; no impide interpretar los tres spans observados. No confundir esta aceptación de un alumno con la preparación simultánea para 16 participantes. Mantener el delay en 0. La capacidad de cohorte, publicación definitiva y materiales docentes son hitos separados.
