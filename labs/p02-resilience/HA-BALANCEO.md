# P02-H — Balanceo y alta disponibilidad a nivel de nodo

Extensión de P02; requiere **dos nodos user Ready y elegibles para scheduling**. Esta práctica NO valida disponibilidad multizona; el node pool actual es regional sin zonas explícitas. Es una ampliación opcional de P02: no forma parte del recorrido CORE ni debe ejecutarse si faltan recursos o permisos.

## Prediccion

- ¿Como distribuye un Service entre varias replicas?
- ¿Que pasa si dos replicas comparten el mismo host y este falla?
- ¿Que protegen realmente un PodDisruptionBudget y topologySpreadConstraints?

## Ejecucion guiada con el instructor

El instructor comprueba antes que existen al menos dos nodos user disponibles y capacidad libre. No necesitas permisos para listar nodos. Solo se modifica el Deployment Orders del namespace propio.

~~~bash
kubectl get pods -l app.kubernetes.io/name=orders -o wide
kubectl patch hpa orders --type=merge -p '{"spec":{"minReplicas":2}}'
kubectl patch deployment orders --type=merge --patch-file labs/p02-resilience/manifests/03-orders-topology-spread.json
kubectl rollout status deployment/orders --timeout=180s
kubectl get pods -l app.kubernetes.io/name=orders -o wide
kubectl apply -f labs/p02-resilience/manifests/04-orders-pdb.yaml
kubectl get pdb orders-ha-demo
kubectl get endpointslice -l kubernetes.io/service-name=orders
~~~

Verificar dos Pods Ready en **distintos nodos** y dos endpoints elegibles del Service. Si no sucede, investigar scheduling, taints, capacidad, quotas y permisos en vez de retirar controles. Con `minDomains: 2` el ejercicio evita que dos réplicas se concentren silenciosamente en un único nodo cuando solo queda un dominio elegible. Si el segundo Pod queda `Pending`, eso es una evidencia diagnóstica, no un motivo para desactivar el requisito.

~~~bash
bash labs/p02-resilience/scripts/verify-ha.sh
~~~

Para observar balanceo, abrir port-forward de Gateway en una terminal y solicitar repetidamente la API desde otra:

~~~bash
kubectl port-forward service/api-gateway 8080:8080
~~~

~~~bash
for i in $(seq 1 15); do
  curl -fsS 'http://localhost:8080/api/orders/preview?sku=SKU-001&quantity=2' | jq -r '.servedBy'
done
~~~

No se garantiza reparto uniforme: el balanceo actua sobre conexiones y puede haber reutilizacion.

## Caida de nodo (solo demostracion de instructor)

No apagar, drenar ni cordonar nodos compartidos desde una cuenta de alumno. El instructor puede programar una prueba de drain controlada **sin alumnos trabajando** y con capacidad para reprogramacion.

Un PDB limita las **evicciones voluntarias** que respetan la API Eviction; no cubre fallos repentinos de nodo, eliminaciones directas de Pods ni ausencia de capacidad. Dos nodos mejoran resiliencia de instancia, pero no implican resiliencia entre zonas ni HA de PostgreSQL.

## Evidencia de alta disponibilidad

Recoge nombres de Pods y `spec.nodeName`, el estado Ready de ambos,
EndpointSlices, la política HPA y el PDB. **Dos réplicas distribuidas** reducen
riesgo ante pérdida de un nodo, pero no demuestran continuidad de negocio ante
fallo de zona, problemas del plano de control ni disponibilidad de Inventory.

## Limpieza

~~~bash
kubectl delete pdb orders-ha-demo --ignore-not-found
kubectl patch hpa orders --type=merge -p '{"spec":{"minReplicas":1}}'
# Elimina explícitamente el campo agregado por kubectl patch: 'apply' por sí solo
# puede no borrarlo porque no estaba en la configuración declarativa original.
if [[ -n "$(kubectl get deployment orders -o jsonpath='{.spec.template.spec.topologySpreadConstraints}')" ]]; then
  kubectl patch deployment orders --type=json \
    -p='[{"op":"remove","path":"/spec/template/spec/topologySpreadConstraints"}]'
fi
kubectl apply -f labs/p02-resilience/manifests/01-orders-probes.yaml
kubectl rollout status deployment/orders --timeout=180s
~~~

