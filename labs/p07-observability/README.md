# P07 — Investigar un incidente distribuido con métricas, trazas y logs

> **Estado: diseño CORE pendiente de implementación y ensayo real. No publicar como lab listo.**  
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

## Piloto 0 — backend de trazas (preparado, pendiente de prueba)

El manifiesto `manifests/01-jaeger-pilot.yaml` crea Jaeger 2.23.0 en el namespace actual, con un Deployment y un Service ClusterIP, sin PVC ni exposición pública. Solo requiere el RBAC ya concedido para Deployments/Services. Se fijan 100m/192Mi de requests y 500m/512Mi de límites; validar consumo real. No representa todavía trazas de la aplicación.

```bash
kubectl apply --dry-run=server -f labs/p07-observability/manifests/01-jaeger-pilot.yaml
kubectl apply -f labs/p07-observability/manifests/01-jaeger-pilot.yaml
kubectl rollout status deployment/p07-jaeger --timeout=180s
kubectl get pods,svc -l app.kubernetes.io/name=p07-jaeger
kubectl port-forward service/p07-jaeger 16686:16686
```

Abrir la UI mediante el puerto privado de Codespaces. El endpoint `/api/services` debe responder; no se espera que aparezcan Orders/Inventory hasta instrumentarlos. Cleanup: `kubectl delete -f labs/p07-observability/manifests/01-jaeger-pilot.yaml`. Jaeger utiliza almacenamiento efímero: se pierden las trazas cuando se recrea el Pod.

## Gate para implementación (instructor)

- Medir capacidad antes de instalar collector, backend de trazas, Prometheus o Grafana.
- Confirmar cómo se genera y propaga `traceparent` a través de los seis servicios Java Spring.
- Acordar mecanismo de inyección de latencia reversible, aislado por alumno y que no altere servicios compartidos.
- Verificar RBAC de lectura y acceso a dashboards; no exponer dashboards públicos sin autenticación.
- Validar instrumentación end-to-end desde un Codespace real y escribir entonces los comandos exactos y el verificador.

## STRETCH (opcional)

Comparar cardinalidad de métricas, retención, sampling y costes; analizar una traza con múltiples dependencias; construir una alerta basada en error budget.

> Este README es una **especificación de trabajo**, no sustituye el laboratorio final. Su finalidad es evitar que el plan de observabilidad se confunda con funcionalidad disponible.
