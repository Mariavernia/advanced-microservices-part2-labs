# P07 — Investigar un incidente distribuido con métricas, trazas y logs

> **Modalidad:** Codespaces en fork + AKS; sin instalaciones locales.  
> **Predecesores:** P01–P06.

## Escenario

La plataforma Advanced Orders está protegida por JWT y tiene mTLS entre Orders e Inventory. El equipo de operaciones recibe avisos de degradación de pedidos. Debes preparar observabilidad, demostrar qué señales son útiles y resolver un incidente sin conocer de antemano su causa.

No desplegarás una plataforma de observabilidad de producción. Utilizarás Jaeger privado para trazas, Actuator para métricas de aplicación, Kubernetes para recursos y logs correlacionados. Jaeger no almacena métricas ni logs en este recorrido.

## CORE 1 — Diseña el camino de las trazas

Precondiciones: seis servicios operativos; Gateway 0.2.0-sec protegido sin rate limiter; Orders e Inventory con Envoy; ninguna PeerAuthentication temporal; una réplica por aplicación. El instructor confirma capacidad para los agentes y Jaeger. No reapliques manifiestos completos de P01.

~~~bash
./scripts/preflight.sh
kubectl get deployment,pod,service
kubectl get peerauthentication
kubectl apply --dry-run=server -f labs/p07-observability/manifests/01-jaeger-pilot.yaml
kubectl apply -f labs/p07-observability/manifests/01-jaeger-pilot.yaml
kubectl rollout status deployment/p07-jaeger --timeout=180s
kubectl get service p07-jaeger -o yaml
kubectl get endpointslice -l kubernetes.io/service-name=p07-jaeger
~~~

Jaeger 2.23.0 utiliza memoria, no PVC ni exposición pública. Identifica los puertos de consulta, OTLP HTTP y OTLP gRPC. Dibuja Gateway → Orders → Inventory y los tres exportadores hacia Jaeger. El backend no recibe trazas hasta instrumentar las aplicaciones.

Terminal A:

~~~bash
kubectl port-forward service/p07-jaeger 16686:16686
~~~

Abre su UI desde Ports de Codespaces con visibilidad Private. Comprueba el backend desde otra terminal:

~~~bash
curl -fsS http://127.0.0.1:16686/api/v3/services
~~~

## CORE 2 — Configura la instrumentación

Copia la plantilla de configuración:

~~~bash
mkdir -p work/p07
cp labs/p07-observability/templates/otel-settings.json work/p07/otel-settings.json
~~~

Completa sus campos en el editor. Requisitos:
- Exportar trazas mediante OTLP HTTP/protobuf al Service interno p07-jaeger, puerto OTLP HTTP y ruta /v1/traces. No uses localhost ni el puerto de la UI.
- Nombre de servicio distinto para cada aplicación: inventory, orders y api-gateway.
- Exportador de trazas otlp; métricas y logs none, porque se consultan por otros canales.
- Sampling parentbased_always_on para este experimento; conserva la decisión del padre y muestrea las nuevas raíces. No es una recomendación universal de producción.

Justifica cómo se distingue una traza de un servicio y por qué el exportador necesita la dirección interna del clúster, no el port-forward de Codespaces.

El helper instrument.sh instala únicamente el agente y realiza un rollout seguro utilizando **tu configuración**. Conserva los recursos anteriores, P05 y P06; reserva 256Mi de memoria y límite 768Mi en las JVM instrumentadas. Añade un initContainer con agente 2.30.0 fijado por digest, emptyDir y startup/readiness adecuadas. No sustituye tu configuración ni valida por sí solo la llegada de trazas. Primero backend:

~~~bash
bash labs/p07-observability/scripts/instrument.sh backend work/p07/otel-settings.json
CONFIRM_P07_INSTRUMENT=YES bash labs/p07-observability/scripts/instrument.sh backend work/p07/otel-settings.json
~~~

Inspecciona las variables OTEL y los contenedores de Orders e Inventory, incluyendo native sidecars. Guarda las revisiones originales indicadas por el helper. Genera el preview de negocio desde Orders y busca sus servicios en Jaeger. No instrumentes Gateway hasta que encuentres una traza con ambos servicios.

~~~bash
kubectl exec deploy/orders -c orders -- curl -fsS 'http://127.0.0.1:8080/api/orders/preview?sku=SKU-001&quantity=2'
bash labs/p07-observability/scripts/instrument.sh gateway work/p07/otel-settings.json
CONFIRM_P07_INSTRUMENT=YES bash labs/p07-observability/scripts/instrument.sh gateway work/p07/otel-settings.json
~~~

Abre un port-forward privado del Gateway a 8080 y realiza una petición autenticada con el lector usando el cliente de P05. Renueva el token si ha expirado.

~~~bash
python3 labs/p05-api-security/scripts/request.py reader '/api/orders/preview?sku=SKU-001&quantity=2'
~~~

Busca una traza nueva que incluya Gateway, Orders e Inventory. Identifica spans cliente/servidor y relaciones padre-hijo. Distingue tiempos inclusivos del tiempo exclusivo: no sumes todos los spans como si fueran independientes. Si no aparecen los servicios, comprueba nombre, exportador, protocolo, endpoint, logs de agente y muestreo. No vuelvas a ejecutar instrument.sh sobre aplicaciones ya instrumentadas.

## CORE 3 — Incidente de telemetría: negocio sano, exportación rota

El equipo observa que las peticiones funcionan pero no aparecen nuevos spans de Inventory. Reproduce el fallo: modifica **solo** OTEL_EXPORTER_OTLP_TRACES_ENDPOINT de Inventory a un hostname de Service inexistente en tu namespace. No modifiques el destino de negocio ni el agente.

~~~bash
# Elige un nombre inexistente; conserva puerto y ruta de OTLP HTTP.
kubectl set env deployment/inventory OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://REEMPLAZAR:4318/v1/traces
kubectl rollout status deployment/inventory --timeout=420s
~~~

Genera nuevas peticiones. Comprueba que la API sigue funcionando, busca trazas nuevas (no históricas) y consulta logs del agente de Inventory. Un backend de trazas sano no garantiza que todos los exportadores entreguen datos. No borres Jaeger ni reinstales la malla.

Diagnostica el endpoint contrastando la configuración real con tu fichero y el Service. Restaura únicamente la variable afectada con el valor correcto de tu fichero, espera rollout, genera otra petición y demuestra que aparecen los spans de Inventory nuevamente. La prueba requiere evidencia positiva tras la recuperación; esperar una traza vieja no es suficiente.

## CORE 4 — Prepara métricas y logs de aplicación

Copia el patch auxiliar y completa solo los dos campos de observabilidad. El resto está preparado.

~~~bash
cp labs/p07-observability/templates/inventory-observability.patch.yaml work/p07/inventory-observability.patch.yaml
~~~

Mantén health e info y habilita metrics en la variable de exposición Actuator. Configura el patrón de logs para incluir trace_id y span_id a partir del MDC (pista: %X{trace_id:-none} y %X{span_id:-none}); conserva hora, nivel, logger y mensaje. No registres JWT ni contraseñas.

~~~bash
kubectl patch deployment inventory --type=strategic --patch-file work/p07/inventory-observability.patch.yaml --dry-run=server -o yaml
kubectl patch deployment inventory --type=strategic --patch-file work/p07/inventory-observability.patch.yaml
kubectl rollout status deployment/inventory --timeout=420s
~~~

La imagen 0.1.0-p07 ya publicada permite simular latencia en el controlador de Inventory con TRAINING_INVENTORY_DELAY_MS, por defecto 0 y acotada a 3000 ms. No afecta a health. Comprueba que la actualización conserva agente, malla y recursos.

## CORE 5 — Experimento guiado: localiza una latencia

Define estas dos funciones auxiliares en Bash. Solo generan una petición con un identificador de traza conocido y consultan métricas; no introducen ni resuelven incidentes.

~~~bash
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

~~~

La función p07_request añade traceparent con un padre externo sintético. Jaeger puede mostrar una traza Incomplete porque ese padre no se exporta; comprueba los spans reales de aplicación.

### A. Línea base

Ejecuta tres peticiones independientes, guarda sus códigos, tiempos e IDs. Consulta p07_metrics, CPU/memoria con kubectl top y logs de Inventory. Calcula TOTAL_TIME / COUNT de la métrica HTTP filtrada por la URI de negocio. Localiza COUNT, TOTAL_TIME y MAX, con sus unidades.

~~~bash
p07_request
p07_request
p07_request
BASELINE_TRACE_ID="$TRACE_ID"
p07_metrics
kubectl top pods
~~~

### B. Perturbación

Predice qué señal cambiará si introduces 1500 ms de latencia en Inventory. Cambia tú el valor con kubectl set env, espera el rollout y repite las peticiones. Registra el ID de una traza lenta y las métricas. Busca el log de la petición mediante ese ID.

~~~bash
kubectl set env deployment/inventory TRAINING_INVENTORY_DELAY_MS=1500
kubectl rollout status deployment/inventory --timeout=420s
p07_request
p07_request
p07_request
INCIDENT_TRACE_ID="$TRACE_ID"
p07_metrics
kubectl logs deployment/inventory -c inventory --tail=100 | grep "$INCIDENT_TRACE_ID"
~~~

Identifica en Jaeger el span receptor lento y el span cliente que lo espera. ¿Qué prueba distingue latencia de aplicación de latencia exclusivamente de red? Compara las medidas antes y después; al recrear Inventory se reinician los contadores, así que no restes contadores entre Pods distintos.

### C. Recuperación

Restaura el valor 0 y comprueba que vuelve a la línea base con nuevas peticiones, métricas y traza. No basta con observar que el Deployment está Ready.

~~~bash
kubectl set env deployment/inventory TRAINING_INVENTORY_DELAY_MS=0
kubectl rollout status deployment/inventory --timeout=420s
p07_request
p07_request
p07_request
RECOVERY_TRACE_ID="$TRACE_ID"
p07_metrics
~~~

Guarda las evidencias de las tres fases antes del reto. Si un experimento falla, restaura igualmente el valor 0 y solicita ayuda.

## CORE 6 — Incidente final: guardia de operaciones

El instructor introducirá una incidencia reversible en tu namespace y te comunicará el síntoma observado, **sin indicar el componente ni la configuración que ha cambiado**. No leas el procedimiento privado del instructor; el objetivo es investigar. Si el instructor no está disponible, conserva las evidencias del experimento guiado y realiza el reto cuando confirme la inyección.

El aviso puede ser degradación de la latencia o fallos en preview de pedidos. No presupongas que se repite la perturbación anterior. Tu tarea:

1. Reproduce el síntoma con peticiones de negocio y registra HTTP, tiempo y alcance. Comprueba health y una ruta distinta para acotar el problema.
2. Formula al menos dos hipótesis y decide qué señal permite distinguirlas. Consulta trazas nuevas; si falta un span, explica si puede significar exportación fallida o una llamada que nunca llegó al receptor.
3. Contrasta métricas, logs correlacionados, endpoints, estado de Pods y configuración de los componentes sospechosos. No imprimas Secrets ni tokens.
4. Identifica una causa respaldada por evidencia. Propón una corrección mínima y aplícala exclusivamente a tu namespace. No borres Pods, reinicies todo ni retires seguridad como estrategia de diagnóstico.
5. Repite las pruebas: contrato de negocio, latencia, traza nueva, logs y estado del rollout. Compara con tu baseline; si la recuperación no es suficiente, sigue investigando.

El instructor confirma la recuperación antes del cierre. Guarda las evidencias y escribe un RCA: síntoma, impacto, causa, prueba, corrección y prevención. No presentes una hipótesis como hecho si no puedes demostrarla.

### Hoja de investigación

| Evidencia | Resultado |
|---|---|
| Petición afectada y HTTP/latencia | |
| Hipótesis 1 / hipótesis 2 | |
| Traza nueva y span relevante o ausente | |
| Métrica y log que apoyan la causa | |
| Configuración antes/después | |
| Prueba de recuperación | |
| Control preventivo / alerta propuesta | |

## CORE 7 — Cierre

Conserva trazas y evidencias antes de retirar Jaeger: su almacenamiento es efímero. Verifica la recuperación de Orders e Inventory y la protección P05. Si el instructor indica limpieza, utiliza su procedimiento de recuperación de revisiones o limpieza de workloads; no apliques P01 encima de la malla ni borres el PVC de P04 por tu cuenta.

Detén los port-forwards. No publiques Jaeger ni Actuator. La instrumentación y Jaeger pueden conservarse hasta la validación final; el instructor elimina los recursos temporales al terminar.

## Evidencia mínima

- Configuración OTEL y patch de métricas/logs creados por ti.
- Trazas reales de backend y Gateway autenticado; fallo de exportación y recuperación.
- Tabla de baseline, perturbación y recuperación con HTTP, duración, COUNT/TOTAL_TIME/MAX.
- RCA del incidente final con evidencia independiente de métrica, traza, log y configuración.
- Una propuesta de alerta que distinga errores, latencia y ausencia de telemetría; explica qué datos harían falta para Prometheus/Grafana y Alertmanager.

## SUPPORT

Si Jaeger no responde, revisa Service, Pod Ready y el túnel privado. Si la JVM no arranca, consulta logs e initContainer del agente; el helper conserva las revisiones previas para recuperación. Si los spans no aparecen, verifica endpoint y protocolo, nombre de servicio, muestreo y retraso de exportación. El instructor comprueba cuotas y capacidad. No amplíes permisos ni cambies los límites del clúster compartido.

## STRETCH

Diseña una alerta por error budget y una estrategia de sampling en producción. Compara almacenamiento de trazas con series temporales y logs centralizados (Prometheus/Grafana, ELK). Propón cómo evitar alta cardinalidad y datos sensibles en atributos. No despliegues plataformas compartidas adicionales.
