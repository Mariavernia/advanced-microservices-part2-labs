# P02-H — Balanceo y alta disponibilidad a nivel de nodo

Extension de P02 preparada para clase; requiere **dos nodos user Ready**. Esta practica NO valida disponibilidad multizona; el node pool actual es regional sin zonas explicitas.

## Prediccion

- ¿Como distribuye un Service entre varias replicas?
- ¿Que pasa si dos replicas comparten el mismo host y este falla?
- ¿Que protegen realmente un PodDisruptionBudget y topologySpreadConstraints?

## Ejecucion guiada con el instructor

Comprobar antes que existen al menos dos nodos user disponibles y capacidad libre. Solo se modifica el Deployment Orders del namespace propio.

~~~bash
kubectl get nodes -L agentpool
kubectl get pods -l app.kubernetes.io/name=orders -o wide
kubectl patch hpa orders --type=merge -p '{"spec":{"minReplicas":2}}'
kubectl patch deployment orders --type=merge --patch-file labs/p02-resilience/manifests/03-orders-topology-spread.json
kubectl rollout status deployment/orders --timeout=180s
kubectl get pods -l app.kubernetes.io/name=orders -o wide
kubectl apply -f labs/p02-resilience/manifests/04-orders-pdb.yaml
kubectl get pdb orders-ha-demo
kubectl get endpointslice -l kubernetes.io/service-name=orders
~~~

Verificar dos Pods Ready en **distintos nodos** y dos endpoints de Service. Si no sucede, investigar scheduling y quotas en vez de retirar controles.

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

## Limpieza

~~~bash
kubectl delete pdb orders-ha-demo --ignore-not-found
kubectl patch hpa orders --type=merge -p '{"spec":{"minReplicas":1}}'
kubectl apply -f labs/p02-resilience/manifests/01-orders-probes.yaml
kubectl rollout status deployment/orders --timeout=180s
~~~

**Pendiente:** prueba real con AKS encendido y dos nodos user.
