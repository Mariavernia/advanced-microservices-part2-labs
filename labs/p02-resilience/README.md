# P02 — Resiliencia, health probes y escalado horizontal

**Modo:** individual, con construcción de manifiestos, experimentos y diagnóstico. **Prerequisito:** P01 desplegado y verificado. Sigue [la metodología de prácticas](../../docs/METODOLOGIA-PRACTICAS.md).

## Escenario

Advanced Orders debe seguir atendiendo pedidos mientras se reemplazan sus instancias. Tu responsabilidad es definir las condiciones de salud, dimensionar Orders y comprobar cómo el HPA y Kubernetes reaccionan ante un fallo y una carga variable.

No vas a aplicar una solución completa de resiliencia. Crearás tus propias configuraciones a partir de plantillas incompletas, tomarás decisiones y las validarás con evidencias.

## Qué debes entregar

- Tus archivos de trabajo: configuración de las tres probes, HPA y generador de carga.
- Evidencia de un Pod Running pero NotReady, su relación con los endpoints y la recuperación.
- Métricas y evolución del HPA con y sin carga. Si no escala, diagnóstico fundamentado; no presentar un escalado manual como autoscaling.
- Evidencia de dos réplicas en distintos nodos y PDB en [P02-H](HA-BALANCEO.md) cuando el instructor confirme capacidad.
- Una decisión justificada sobre resiliencia y recursos, no solamente el resultado del verificador.

## CORE 1 — Punto de partida y contrato de salud

Trabaja desde la raíz del repositorio, en tu namespace asignado.

~~~bash
./scripts/preflight.sh
bash labs/p01-complete-platform/scripts/verify.sh
kubectl get deployment orders
kubectl get endpointslice -l kubernetes.io/service-name=orders
kubectl get deployment orders -o json | jq '.spec.template.spec.containers[] | select(.name=="orders") | {resources,startupProbe,readinessProbe,livenessProbe}'
~~~

Dibuja el recorrido Service → EndpointSlice → Pod. Antes de modificar nada, predice qué sucederá si una réplica está Running pero no está Ready.

Explora los endpoints de Spring Boot Actuator desde el contenedor Orders:

~~~bash
kubectl exec deploy/orders -c orders -- curl -fsS http://127.0.0.1:8080/actuator/health
kubectl exec deploy/orders -c orders -- curl -fsS http://127.0.0.1:8080/actuator/health/readiness
kubectl exec deploy/orders -c orders -- curl -fsS http://127.0.0.1:8080/actuator/health/liveness
~~~

Identifica qué señala cada endpoint. Una respuesta UP no demuestra por sí sola que todo el negocio funciona. Utiliza también el preview de pedidos de P01 para confirmar Orders → Inventory.

## CORE 2 — Construye las probes y la reserva de CPU

Copia las plantillas de trabajo. Los campos marcados TODO no son una configuración funcional.

~~~bash
mkdir -p work/p02
cp labs/p02-resilience/templates/01-orders-probes.patch.yaml work/p02/orders-probes.patch.yaml
cp labs/p02-resilience/templates/02-orders-hpa.yaml work/p02/orders-hpa.yaml
~~~

Abre **work/p02/orders-probes.patch.yaml** en el editor de Codespaces. Completa los campos TODO tú mismo. No copies directamente el manifiesto de recuperación.

Requisitos de ingeniería:

| Campo | Requisito |
|---|---|
| startupProbe | Endpoint de salud general; permite un arranque lento de la JVM. Usa una ventana aproximada entre 150 y 240 segundos (periodSeconds × failureThreshold). |
| readinessProbe | Endpoint de readiness; retira del tráfico una instancia no preparada. Busca una ventana nominal de detección de 10 a 20 segundos. |
| livenessProbe | Endpoint de liveness; reinicia una instancia irrecuperable. Busca una ventana nominal de 25 a 40 segundos. |
| CPU request | 100m, para mantener comparable el experimento HPA. Conserva límite 400m y memoria existente. |
| Puerto y seguridad | Conserva puerto http, usuario no root, imagen, variables y configuración del contenedor. |

Selecciona valores enteros positivos para periodSeconds y failureThreshold. El producto es una aproximación de la ventana de detección, no una garantía exacta. El timeout de cada petición de sonda permanece en 2 segundos.

Justifica por qué readiness debe detectar un problema antes de provocar reinicios innecesarios; explica qué riesgo habría si liveness dependiera de todas las bases de datos y servicios remotos.

Valida tu configuración en el servidor y aplica tu propio patch:

~~~bash
kubectl patch deployment orders --type=strategic \
  --patch-file work/p02/orders-probes.patch.yaml --dry-run=server -o yaml
kubectl patch deployment orders --type=strategic \
  --patch-file work/p02/orders-probes.patch.yaml
kubectl rollout status deployment/orders --timeout=300s
kubectl describe deployment orders
kubectl get pods -l app.kubernetes.io/name=orders
~~~

El patch estratégico selecciona el contenedor por nombre; no reemplaza toda la lista de contenedores. Comprueba las tres probes, las reservas y el estado Ready. Si algo falla, consulta los eventos y los logs antes de volver a aplicar.

**Checkpoint:** muestra los tres endpoints y tus parámetros reales, calcula las ventanas nominales y comprueba una petición de negocio satisfactoria. Tu configuración debe quedar guardada en work/p02.

## CORE 3 — Avería de readiness y diagnóstico

Antes de provocar el fallo, registra el Pod sano y el EndpointSlice. A continuación, **edita tu patch** y cambia únicamente el path de readiness por una ruta HTTP inexistente. No modifiques liveness ni startup.

~~~bash
kubectl patch deployment orders --type=strategic \
  --patch-file work/p02/orders-probes.patch.yaml
kubectl get pods -l app.kubernetes.io/name=orders -w
~~~

Detén el watch con Ctrl+C cuando tengas evidencia. Obtén los siguientes datos:

~~~bash
kubectl describe pods -l app.kubernetes.io/name=orders
kubectl get endpointslice -l kubernetes.io/service-name=orders -o yaml
kubectl rollout status deployment/orders --timeout=30s || true
~~~

Completa con valores reales:

| Evidencia | Observación |
|---|---|
| Pod anterior y Pod nuevo | |
| READY y reinicios de cada Pod | |
| Endpoint anterior y nuevo, condición ready | |
| Rollout y evento de la sonda | |
| Respuesta de negocio vía Gateway | |

Explica por qué el Pod nuevo puede seguir Running sin estar Ready y por qué el rollout puede conservar la réplica anterior. Comprueba la respuesta de negocio usando el port-forward de P01: no presupongas que ha fallado solo porque el rollout no termina.

**Recuperación:** vuelve a editar tu patch para restaurar el endpoint correcto, aplícalo y verifica de nuevo el rollout, EndpointSlice y preview.

~~~bash
kubectl patch deployment orders --type=strategic \
  --patch-file work/p02/orders-probes.patch.yaml
kubectl rollout status deployment/orders --timeout=300s
kubectl get pods -l app.kubernetes.io/name=orders
kubectl get endpointslice -l kubernetes.io/service-name=orders
~~~

No ejecutes un rollback a ciegas: la configuración de trabajo debe reflejar el estado que quieres conservar.

## CORE 4 — Diseña el HPA

Abre **work/p02/orders-hpa.yaml**. Configura un HPA autoscaling/v2 sobre Orders con mínimo 1 réplica, máximo 3, objetivo de utilización CPU del 60% y ventana de estabilización de reducción de 120 segundos. Los límites se mantienen acotados porque trabajamos en infraestructura compartida.

Antes de aplicarlo responde:

- ¿Cuántos millicores representan el 60% de una reserva de 100m?
- Si una réplica consume 150m de CPU, ¿cuántas réplicas recomendaría la fórmula ideal del HPA? Aplica también el máximo configurado.
- ¿Qué cambiaría si la reserva fuera 200m sin cambiar la utilización real?
- ¿Por qué el HPA no arregla automáticamente una dependencia caída?

~~~bash
kubectl apply --dry-run=server -f work/p02/orders-hpa.yaml
kubectl apply -f work/p02/orders-hpa.yaml
kubectl get hpa orders
kubectl top pods -l app.kubernetes.io/name=orders
kubectl describe hpa orders
~~~

Espera muestras de CPU válidas: un HPA recién creado puede mostrar <unknown>. Comprueba ScalingActive y registra el valor de CPU y las réplicas actuales. Para comparar un escalado desde el estado base, espera a que quede una réplica estable. Si la CPU en reposo mantiene más réplicas, registra la situación y consulta al instructor antes de introducir carga.

## CORE 5 — Demuestra escalado bajo carga

**Objetivo:** comprobar si peticiones reales producen escalado, no solo si existe un HPA. El generador de carga es un recurso auxiliar, no la solución del ejercicio.

El instructor coordina el inicio de los experimentos en lotes pequeños. No ejecutes carga contra un servicio público, otro namespace o durante la práctica de un compañero sin coordinación.

Copia y revisa el Job acotado:

~~~bash
cp labs/p02-resilience/manifests/05-orders-load.yaml work/p02/orders-load.yaml
~~~

Identifica su destino interno Orders, los límites CPU/memoria, activeDeadlineSeconds, número de workers y la pausa entre peticiones. El Job tiene un único Pod, no se reintenta al fallar y se detiene por su propio límite temporal. No modifica el Deployment de negocio.

Selecciona en tu archivo WORKERS=1 o 2. Antes de ejecutar, predice el efecto sobre CPU, latencia y réplicas. No superes 4 workers.

Terminal A — observa el HPA:

~~~bash
kubectl get hpa orders -w
~~~

Terminal B — crea el Job y observa:

~~~bash
kubectl apply --dry-run=server -f work/p02/orders-load.yaml
kubectl apply -f work/p02/orders-load.yaml
kubectl get pods -l app.kubernetes.io/name=p02-orders-load
kubectl logs -f job/p02-orders-load
~~~

Si el Pod todavía está Pending o ContainerCreating, consulta sus eventos y vuelve a abrir los logs cuando arranque.

Terminal C — obtiene muestras mientras el Job trabaja:

~~~bash
kubectl top pods -l app.kubernetes.io/name=orders
kubectl get pods -l app.kubernetes.io/name=orders -o wide
kubectl describe hpa orders
~~~

Registra al menos la CPU, CURRENT/TARGET del HPA, réplicas actuales/deseadas y cualquier evento SuccessfulRescale. Al terminar el Job, guarda sus contadores HTTP_200 y errors. La finalización del Job no implica que todas las peticiones hayan sido correctas.

~~~bash
kubectl get job p02-orders-load
kubectl logs job/p02-orders-load
kubectl delete job p02-orders-load --ignore-not-found
~~~

Si no aumentan las réplicas, comprueba si la utilización cruzó el objetivo. Si el instructor confirma capacidad, repite con más workers (hasta 4), modificando tu archivo y creando un Job nuevo después de eliminar el anterior. No aumentes los límites ni el número máximo de réplicas.

### Si el tráfico HTTP no basta: experimento de CPU controlado

Con autorización del instructor, y **solo en tu propio namespace**, puedes aislar la reacción del HPA a CPU consumiendo CPU dentro del contenedor Orders. Esto es un experimento de CPU, no una simulación realista de peticiones de clientes.

Primero confirma que no hay un Job de carga activo y que Orders tiene su límite de 400m. Comprueba que existe timeout:

~~~bash
kubectl exec deploy/orders -c orders -- sh -c 'command -v timeout'
~~~

En una terminal separada, mientras observas HPA y métricas:

~~~bash
kubectl exec deploy/orders -c orders -- timeout 120s sh -c 'while :; do :; done'
~~~

El proceso finaliza automáticamente (el código 124 de timeout es esperado). No lances varias copias. El límite de CPU del contenedor acota el consumo total del proceso Java y la carga. Si la operación de negocio o las probes empeoran, detén el experimento y avisa al instructor. Si el proceso no está disponible, no instales herramientas ni improvises carga.

Compara este resultado con la prueba HTTP. El HPA solo escala cuando su política y métricas lo justifican; no se garantiza un aumento si las métricas, cuotas o capacidad no lo permiten.

### Recuperación tras la carga

No dejes Jobs activos. Observa las muestras de CPU al retirar la carga y la reducción posterior de réplicas. La estabilización evita una reducción inmediata; no exige que el HPA baje a una réplica si la demanda real sigue por encima del objetivo.

**Evidencia obligatoria:** registra estado inicial, pico observado, acción del controlador (o causa demostrada de ausencia de escalado), y estado tras quitar carga. Distingue métricas de CPU, latencia y disponibilidad. Si no se produjo escalado, informa al instructor; no simules un éxito con kubectl scale.

## CORE 6 — Alta disponibilidad y balanceo

Cuando el instructor confirme dos nodos de aplicaciones elegibles y capacidad, continúa con [P02-H](HA-BALANCEO.md). Diseña la distribución por hostname y un PDB, verifica dos réplicas en nodos distintos y observa el balanceo del Service. Si no hay capacidad, se aplaza la ejecución; no se elimina la restricción para simular alta disponibilidad.

No apagues ni drenes nodos compartidos. La demostración de pérdida de nodo, si se realiza, es responsabilidad del instructor.

## CORE 7 — Verificación y cierre

Antes del verificador, asegúrate de haber terminado P02-H y restaurado su mínimo HPA a 1 y retirado PDB/topologySpreadConstraints, o de no haber aplicado esa extensión. Conserva tus probes de CORE 2.

~~~bash
bash labs/p02-resilience/scripts/verify.sh
~~~

El verificador comprueba configuración y disponibilidad de métricas. **No puede sustituir las evidencias del experimento de escalado.** Guarda tus archivos work/p02 y las observaciones en tu fork, sin credenciales.

Tras registrar las evidencias, devuelve la plataforma a una sola réplica para las prácticas siguientes. Elimina el HPA y el Job de esta práctica; conserva las probes y recursos de Orders.

~~~bash
kubectl delete job p02-orders-load --ignore-not-found
kubectl delete hpa orders --ignore-not-found
kubectl scale deployment orders --replicas=1
kubectl rollout status deployment/orders --timeout=300s
bash labs/p01-complete-platform/scripts/verify.sh
~~~

La retirada del HPA es una decisión de cierre del laboratorio, no una configuración recomendada para producción.

## SUPPORT — Diagnóstico y recuperación

| Síntoma | Qué investigar |
|---|---|
| Pod Running, NotReady | Path de readiness, eventos, EndpointSlice |
| Pod reinicia | Startup/liveness, límites de memoria, logs del contenedor anterior |
| HPA <unknown> | Requests CPU, API de métricas, kubectl top, condiciones del HPA |
| CPU por encima del objetivo sin aumento | Ventana de reconciliación, réplicas deseadas, máximo, cuota y scheduling |
| Nuevos Pods Pending | Eventos FailedScheduling/FailedCreate; instructor comprueba cuotas y nodos |
| Job Pending o fallido | Eventos del Job/Pod, imagen, recursos y contadores HTTP |

~~~bash
kubectl get events --sort-by=.lastTimestamp | tail -n 25
kubectl logs deployment/orders --tail=50
kubectl describe deployment orders
kubectl describe hpa orders
kubectl describe job p02-orders-load
kubectl auth can-i list pods.metrics.k8s.io
~~~

Si necesitas recuperar un entorno bloqueado, avisa al instructor. Los manifiestos **manifests/01-orders-probes.yaml** y **manifests/02-orders-hpa.yaml** son referencias de recuperación, no el recorrido de construcción. No reapliques el Deployment completo mientras un HPA gestiona sus réplicas ni después de introducir otros cambios de módulos posteriores.

## STRETCH — Diseña una mejora

Compara tu configuración de probes con otra más agresiva y razona qué ocurriría con un arranque lento. Propón un HPA para una cola de trabajo, identifica la métrica y explica por qué CPU podría ser insuficiente. No cambies las métricas del clúster compartido.

## Debrief

Entrega predije, cambié, observé y concluyo para las probes y el HPA. Defiende una decisión usando tus mediciones. ¿Qué protege cada mecanismo y qué problema queda sin resolver?
