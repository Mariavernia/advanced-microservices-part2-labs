# P04 — Estado duradero y caché en Advanced Orders

**Modo:** individual. **Prerequisito:** acceso a un namespace de alumno y P01 validado.
**Outcome CORE:** demostrar con evidencia por qué un cambio de Pod no debe perder datos transaccionales y por qué una caché no es la fuente de verdad.

## Escenario y límite didáctico

El equipo necesita conservar borradores de pedidos durante reinicios y acelerar la lectura de una proyección. Creamos una base PostgreSQL con PVC, y Redis con almacenamiento efímero.

Esta primera práctica opera el dato mediante psql y redis-cli **para aislar los conceptos de persistencia e invalidación**. Todavía no modifica el código Java de Orders para escribir pedidos; la integración aplicación/DB es una ampliación posterior y no debe presentarse como implementada.

**Advertencia de seguridad:** credenciales aleatorias sintéticas generadas por el alumno. PostgreSQL y Redis no se exponen al exterior. La configuración NO es una propuesta de bases de datos productivas sin TLS/ACL/backups.

## CORE 1 — Predice el estado

Antes de desplegar, inspecciona los manifiestos. Localiza la diferencia entre StatefulSet y Deployment, el PVC en volumeClaimTemplates y la configuración de Redis que desactiva la persistencia local.

¿Qué recurso sería irreemplazable ante la pérdida de un nodo? ¿Qué puede reconstruirse?

## CORE 2 — Desplegar y verificar

~~~bash
./scripts/preflight.sh
bash labs/p04-state-and-cache/scripts/deploy.sh
bash labs/p04-state-and-cache/scripts/verify.sh
kubectl get statefulsets,deployments,pods,pvc,services
kubectl get pvc dbdata-orders-db-0
~~~

Si el PVC está Pending, inspecciona los eventos de Kubernetes y la StorageClass:

~~~bash
kubectl get storageclass
kubectl describe pvc dbdata-orders-db-0
kubectl describe pod orders-db-0
~~~

No borres PVC para resolver un problema de permisos o provisión.

## CORE 3 — Registrar un borrador en PostgreSQL

~~~bash
kubectl exec -i orders-db-0 -- sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -U orders -d ordersdb' <<'SQL'
CREATE TABLE IF NOT EXISTS order_drafts (
  id TEXT PRIMARY KEY,
  sku TEXT NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0)
);
INSERT INTO order_drafts (id, sku, quantity) VALUES ('LAB-001','SKU-001',2)
ON CONFLICT (id) DO UPDATE SET quantity=EXCLUDED.quantity;
SELECT * FROM order_drafts;
SQL
~~~

Pregunta: ¿dónde está realmente almacenada la fila? ¿En la memoria del contenedor, en su capa de escritura o en el volumen persistente?

## CORE 4 — Cachear una lectura y provocar su pérdida

~~~bash
kubectl exec deployment/orders-cache -- redis-cli SET order:LAB-001 "SKU-001:2" EX 600
kubectl exec deployment/orders-cache -- redis-cli GET order:LAB-001
kubectl get pod -l app.kubernetes.io/name=orders-cache
~~~

En un entorno de prueba, elimina el Pod de caché, espera el reemplazo y vuelve a consultar:

~~~bash
kubectl delete pod -l app.kubernetes.io/name=orders-cache
kubectl rollout status deployment/orders-cache
kubectl exec deployment/orders-cache -- redis-cli GET order:LAB-001
~~~

La caché puede haber perdido la clave. Si ha expirado antes por TTL, repite el experimento y diferencia TTL de reinicio.

## CORE 5 — Reiniciar la base sin eliminar su volumen

~~~bash
kubectl delete pod orders-db-0
kubectl rollout status statefulset/orders-db --timeout=240s
kubectl exec orders-db-0 -- sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U orders -d ordersdb -Atc "SELECT id,sku,quantity FROM order_drafts"'
kubectl get pvc dbdata-orders-db-0
~~~

La fila LAB-001 debe persistir. Compara el comportamiento de la base y la caché y explica la relación entre estabilidad de datos e identidad de Pods.

## SUPPORT

~~~bash
kubectl describe statefulset orders-db
kubectl logs orders-db-0
kubectl get events --sort-by=.lastTimestamp | tail -n 25
kubectl describe pvc dbdata-orders-db-0
~~~

Si PostgreSQL rechaza acceso, verifica que el Secret orders-postgres-auth existe. Nunca pegues la contraseña en el chat ni la incluyas en un commit.

## STRETCH

Propón un patrón cache-aside con claves, TTL e invalidación al cambiar order_drafts. Analiza qué lecturas obsoletas tolerarías y cuáles no.

## Evidencia y debrief

Documenta tres capturas o extractos: (1) fila insertada, (2) mismo registro tras reiniciar Pod PostgreSQL, (3) pérdida o expiración de caché. Explica por qué **persistencia de volumen no equivale a backup**, y qué cambiarías para producción: identidad, secretos, TLS, réplicas, recuperación y costes.

**Estado:** manifiestos y recorrido preparados; requieren ensayo de imagen, StorageClass y PVC en AKS antes de clase. No representa todavía persistencia integrada en los microservicios Java.
