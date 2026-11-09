# P02 — Resiliencia, health probes y escalado horizontal

**Modo:** individual. **Prerequisito:** P01 desplegado y verificado con Orders e Inventory.
**Evidencia de salida:** diferenciar Pod vivo de Pod preparado, provocar y recuperar un fallo de readiness, explicar el alcance de HPA.

## Escenario

Advanced Orders funciona con seis servicios, pero todavía carece de señales de salud explícitas. ¿Qué ocurre si una instancia está Running pero no puede atender tráfico? ¿Puede un HPA arreglar una dependencia caída?

## CORE 1 — Punto de partida y predicción

~~~bash
./scripts/preflight.sh
bash labs/p01-complete-platform/scripts/verify.sh
kubectl get deployment orders
kubectl get endpointslice -l kubernetes.io/service-name=orders
~~~

Antes de continuar: predice cómo cambia el tráfico cuando la ruta de readiness deja de responder.

## CORE 2 — Tres probes distintas

Abre manifests/01-orders-probes.yaml. Localiza startupProbe, readinessProbe y livenessProbe. Relaciona cada una con una decisión del kubelet y/o del Service.

~~~bash
kubectl apply -f labs/p02-resilience/manifests/01-orders-probes.yaml
kubectl rollout status deployment/orders --timeout=180s
kubectl describe deployment orders
kubectl get pods -l app.kubernetes.io/name=orders
~~~

Pregunta: ¿por qué no conviene usar la disponibilidad de todas las dependencias como liveness de Orders?

## CORE 3 — Avería controlada

Cambiarás solamente el endpoint de readiness del Deployment. No es necesario tocar código, secretos ni el clúster compartido.

~~~bash
kubectl patch deployment orders --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/sin-readiness"}]'
kubectl get pods -l app.kubernetes.io/name=orders -w
~~~

Detén el watch con Ctrl+C. Obtén evidencias:

~~~bash
kubectl describe pods -l app.kubernetes.io/name=orders
kubectl get endpointslice -l kubernetes.io/service-name=orders -o yaml
kubectl rollout status deployment/orders --timeout=30s || true
~~~

**Checkpoint:** identifica Pod Running, Pod Ready, destinos activos del Service y la razón por la que Kubernetes puede mantener temporalmente la revisión anterior durante un rollout.

Restaura la definición del repositorio:

~~~bash
kubectl apply -f labs/p02-resilience/manifests/01-orders-probes.yaml
kubectl rollout status deployment/orders --timeout=180s
~~~

Si el cambio imperativo persiste por conflicto de historial, inspecciona kubectl rollout history y utiliza kubectl rollout undo deployment/orders, confirmando siempre qué revisión restauras.

## CORE 4 — HPA y límites

~~~bash
kubectl apply -f labs/p02-resilience/manifests/02-orders-hpa.yaml
kubectl get hpa orders
kubectl top pods
kubectl describe hpa orders
~~~

Identifica requests.cpu=100m y averageUtilization=60%. ¿60% significa 60% de una CPU? Razona sobre la métrica relativa a requests. No esperes necesariamente observar escalado: unas pocas peticiones pueden no provocar suficiente carga.

## SUPPORT

~~~bash
kubectl get events --sort-by=.lastTimestamp | tail -n 25
kubectl logs deployment/orders --tail=30
kubectl get pod -l app.kubernetes.io/name=orders -o wide
kubectl get endpointslice -l kubernetes.io/service-name=orders
~~~

Si HPA muestra valores desconocidos, comprueba que Metrics Server tiene muestras recientes. No cambies cuotas o autorizaciones del clúster como solución.

## Extensión P02-H — Balanceo y disponibilidad a nivel de nodo

Después de configurar las probes y el HPA, puedes realizar la extensión
[HA-BALANCEO.md](HA-BALANCEO.md). **No forma parte de la verificación CORE**:
requiere dos nodos de aplicaciones Ready y con capacidad disponible. Si el
clúster está apagado o los nodos no son accesibles, no ejecutes ni intentes
modificar la infraestructura compartida.

En P02-H se demuestra distribución entre nodos mediante
`topologySpreadConstraints`, se observa el comportamiento de `Service` y se
analiza el alcance de un `PodDisruptionBudget`. El fallo de nodo/drain solo
puede ejecutarlo el instructor en condiciones controladas.

La verificación específica es:

~~~bash
bash labs/p02-resilience/scripts/verify-ha.sh
~~~

## STRETCH

Compara readiness del proceso y readiness que verifica dependencias remotas. ¿Qué modos de fallo pueden generar tormentas de reinicio? ¿Qué métricas usarías para autoscaling de una cola?

## Verificación y debrief

~~~bash
bash labs/p02-resilience/scripts/verify.sh
~~~

1. ¿Puede un contenedor estar Running sin estar Ready?
2. ¿Qué condiciones permiten que un Service envíe tráfico a una réplica?
3. ¿Qué hace el HPA ante una dependencia caída?
4. ¿Por qué un recurso con limits no equivale a garantizar capacidad disponible?

**Estado del laboratorio:** preparado en Git. La validación end-to-end requiere un AKS encendido y un usuario real de alumno.
