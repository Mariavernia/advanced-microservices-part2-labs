# P07 — Investigar un incidente distribuido con métricas, trazas y logs

> **Estado: Jaeger, instrumentación Java y traza Orders → Inventory validados en student02 (12/11/2026). Gateway instrumentado y Ready; pendiente traza completa autenticada, incidente y aceptación CORE.**  
> **Modalidad:** Codespaces en fork + AKS; sin instalaciones locales.  
> **Predecesores:** P01–P06.

## Incidente propuesto (para instrumentar y ensayar)

Una petición a `Orders` tarda demasiado o falla porque `Inventory` introduce latencia. El alumno debe contestar con pruebas:

1. ¿El usuario percibe error o latencia? ¿En qué endpoint?
2. ¿Qué microservicio es responsable? ¿Cómo separas dependencia/infraestructura?
3. ¿Qué señal aportan métricas, logs y **trazas distribuidas reales**?
4. ¿Cómo verificas recuperación y diferencia entre síntoma y causa?

El diseño inicial contemplaba observabilidad compartida. Para el primer piloto se utiliza **Jaeger temporal y privado en student02**, con almacenamiento en memoria y acceso por port-forward. Así evitamos que alumnos distintos puedan consultar trazas ajenas. La arquitectura definitiva de clase (compartida con aislamiento o instancias efímeras por namespace) se decidirá tras medir consumo y concurrencia.

## Recorrido propuesto (sin comandos operativos ficticios)

**CORE 1 — Señal:** reproducir la respuesta de la API y medir duración/tasa de error. Registrar qué puede observarse solo con `curl`.

**CORE 2 — Métrica:** inspeccionar métricas de servicio y Kubernetes ya desplegadas, distinguir CPU/memoria de duración HTTP; correlacionar temporalmente con el fallo.

**CORE 3 — Traza:** identificar un `trace_id` que conecte Gateway → Orders → Inventory y localizar el span lento. **No afirmar que la traza existe hasta instrumentar/exportar y verificar el flujo real**.

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

El helper añade el agente oficial OpenTelemetry Java 2.30.0 mediante initContainer y emptyDir, configura JAVA_TOOL_OPTIONS, nombres de servicio y OTLP HTTP/protobuf hacia Jaeger dentro del mismo namespace. Conserva imágenes y variables existentes de P05 y etiquetas P06. Ajusta memoria de las aplicaciones instrumentadas a 256Mi request y 768Mi limit para el piloto. Añade startupProbe (hasta 300 s antes de habilitar liveness) y readinessProbe HTTP; se conservan las sondas liveness existentes. Si falla un rollout, recoge estados y logs de la revisión fallida antes de intentar recuperar las revisiones originales de esa fase. El fallo de Gateway no revierte Orders e Inventory ya instrumentados en la fase backend. Validación real: una traza de negocio Orders → Inventory con 3 spans (10,7 ms total, 6,4 ms cliente HTTP, 2,6 ms servidor Inventory). Gateway instrumentado y Ready; falta verificar petición autenticada completa con los tres servicios. Las métricas y logs OTLP están deshabilitados en esta fase, porque Jaeger es backend de trazas. 

## Gate para implementación (instructor)

- Medir capacidad antes de instalar collector, backend de trazas, Prometheus o Grafana.
- Confirmar cómo se genera y propaga `traceparent` a través de los seis servicios Java Spring.
- Acordar mecanismo de inyección de latencia reversible, aislado por alumno y que no altere servicios compartidos.
- Verificar RBAC de lectura y acceso a dashboards; no exponer dashboards públicos sin autenticación.
- Validar instrumentación end-to-end desde un Codespace real y escribir entonces los comandos exactos y el verificador.

## STRETCH (opcional)

Comparar cardinalidad de métricas, retención, sampling y costes; analizar una traza con múltiples dependencias; construir una alerta basada en error budget.

> Este README es una **especificación de trabajo**, no sustituye el laboratorio final. Su finalidad es evitar que el plan de observabilidad se confunda con funcionalidad disponible.

## 12/11/2026 — Evidencia del piloto

- Jaeger 2.23.0, API v3, backend privado en student02. Exportación real de inventory/orders.
- Primer ensayo de Gateway: liveness reiniciaba el proceso antes de escuchar en 8080; la instrumentación se separó en backend y gateway, añadió startup/readiness probes y diagnóstico previo a rollback.
- Rollouts corregidos: Inventory y Orders 2/2 con proxy nativo, Gateway 1/1 sin sidecar, todos instrumentados y sin reinicios nuevos. Cinco previews HTTP 200 con canBeFulfilled=true.
- Captura Jaeger: trace ID `1f5c1b1659d115ab6de79f48ab8621bd`, 2 servicios, 3 spans, 10.7 ms total. Orders client 6.4 ms, Inventory server 2.6 ms.
- No confundir el arranque saludable del Gateway con validación de autenticación ni con prueba de la traza completa.

## Piloto 2 — Incidente de latencia (código preparado, imagen aún por construir)

Inventory añade una propiedad de entrenamiento `training.inventory.delay-ms` (variable `TRAINING_INVENTORY_DELAY_MS`), con valor por defecto 0 y máximo efectivo de 3000 ms. La latencia se introduce en el controlador para que aparezca dentro del span receptor y se registra con un warning; no afecta a las sondas Actuator. No aplicar a imágenes P01–P06 ni publicar un tag existente.

El instructor construirá el nuevo tag `advancedorders/inventory:0.1.0-p07` en ACR desde esta rama. Luego se cambiará solamente la imagen del Deployment Inventory en el namespace piloto, preservando sus sidecars y su agente. Se habilitará el endpoint interno Actuator metrics para observar `http.server.requests` y se añadirá trace_id/span_id al patrón de logs. Primero validar delay=0; después comparar con delay=1500 y restaurar 0. Los detalles operativos se cerrarán tras probar la imagen.
