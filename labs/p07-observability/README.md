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

El alumno no instalará Prometheus/Grafana/Jaeger en su namespace. La infraestructura de observabilidad será compartida y administrada por el instructor para limitar costes, seguridad y carga del AKS.

## Recorrido propuesto (sin comandos operativos ficticios)

**CORE 1 — Señal:** reproducir la respuesta de la API y medir duración/tasa de error. Registrar qué puede observarse solo con `curl`.

**CORE 2 — Métrica:** inspeccionar métricas de servicio y Kubernetes ya desplegadas, distinguir CPU/memoria de duración HTTP; correlacionar temporalmente con el fallo.

**CORE 3 — Traza:** identificar un `trace_id` que conecte Gateway → Orders → Inventory y localizar el span lento. **No afirmar que la traza existe hasta instrumentar/exportar y verificar el flujo real**.

**CORE 4 — Logs:** filtrar logs de la petición/trace_id sin publicar secretos ni JWT. Diferenciar log local de correlación distribuida.

**CORE 5 — Recuperación:** revertir el fallo inducido, comprobar que mejoran las señales y redactar RCA de 5 líneas con evidencias.

## Gate para implementación (instructor)

- Medir capacidad antes de instalar collector, backend de trazas, Prometheus o Grafana.
- Confirmar cómo se genera y propaga `traceparent` a través de los seis servicios Java Spring.
- Acordar mecanismo de inyección de latencia reversible, aislado por alumno y que no altere servicios compartidos.
- Verificar RBAC de lectura y acceso a dashboards; no exponer dashboards públicos sin autenticación.
- Validar instrumentación end-to-end desde un Codespace real y escribir entonces los comandos exactos y el verificador.

## STRETCH (opcional)

Comparar cardinalidad de métricas, retención, sampling y costes; analizar una traza con múltiples dependencias; construir una alerta basada en error budget.

> Este README es una **especificación de trabajo**, no sustituye el laboratorio final. Su finalidad es evitar que el plan de observabilidad se confunda con funcionalidad disponible.
