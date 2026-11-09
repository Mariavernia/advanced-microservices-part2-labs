# P04 — Estado persistente, almacenamiento y caché

**Modo:** individual, desde Codespaces. **Prerequisitos:** sesión autenticada, namespace personal, P01 operativo.  
**Escenario:** Advanced Orders. **Rol:** ingeniero responsable de garantizar que un borrador de pedido sobreviva al reemplazo de un Pod sin servir datos antiguos desde la caché.

## Qué queremos demostrar

Una instancia de **Orders** debe ser sustituible. No queremos depender de la memoria local de sus Pods para conservar un estado de negocio. En esta práctica investigaremos dos mecanismos con comportamientos distintos:

- **PostgreSQL**: estado de negocio persistente mediante un **StatefulSet** y un volumen persistente.
- **Redis**: caché de lectura en un **Deployment** sin volumen persistente; puede perder información y entregar una vista obsoleta.

**Límite del ejercicio:** la escritura/lectura se realiza de forma explícita con herramientas de diagnóstico `psql` y `redis-cli`, simulando lo que haría Orders. **La API HTTP de Orders todavía no utiliza automáticamente estas bases de datos**. El objetivo de esta fase es comprender el comportamiento operacional y el contrato de consistencia antes de integrar código. No confundas el experimento con una implementación completa del backend.

## Al finalizar deberías poder

1. Explicar por qué PostgreSQL usa StatefulSet, Service headless y PVC.
2. Demostrar con evidencia que un dato persiste aunque desaparezca el Pod de la base de datos.
3. Provocar una inconsistencia observable entre PostgreSQL y Redis y corregirla.
4. Explicar qué significa *cache invalidation* y qué no garantiza un TTL por sí solo.
5. Distinguir retención de PVC, backup, alta disponibilidad y recuperación ante desastres.

## CORE A — Inspecciona el diseño antes de desplegar

Localiza `manifests/01-orders-db.yaml` y `manifests/02-orders-cache.yaml`.
Sin ejecutar todavía, responde:

- ¿Qué tipo de controlador usa cada componente?
- ¿Qué diferencia hay entre un Service normal y un Service `clusterIP: None`?
- ¿De dónde toma PostgreSQL su contraseña? ¿Dónde queda almacenada?
- ¿Qué recurso conserva los datos después de desaparecer `orders-db-0`?
- ¿Qué opciones del comando de Redis desactivan la persistencia?

Consulta el namespace seleccionado y ejecuta el preflight:

```bash
./scripts/preflight.sh
kubectl config view --minify -o jsonpath='{..namespace}'; echo
```

## CORE B — Desplegar almacenamiento aislado

```bash
bash labs/p04-state-and-cache/scripts/deploy.sh
kubectl get statefulsets,deployments,services,pvc
kubectl describe statefulset orders-db
kubectl get pvc dbdata-orders-db-0
kubectl get storageclass
```

Comprueba que PostgreSQL y Redis tienen Pods listos. No añadas `namespace` a los
manifiestos ni crees recursos fuera del tuyo.

**Checkpoint:** identifica el nombre del PVC y explica por qué aparece aunque
el manifiesto no declare un PVC independiente.

## CORE C — Un borrador en PostgreSQL

El siguiente comando crea una tabla de prácticas y un borrador idempotente
(en cada namespace existe su propio registro de prueba):

```bash
bash labs/p04-state-and-cache/scripts/seed-demo.sh
```

Lee el estado real:

```bash
kubectl exec orders-db-0 -- sh -c \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -U orders -d ordersdb -At \
   -c "SELECT order_id, sku, quantity, status FROM course_order_drafts WHERE order_id = '\''ORD-DEMO-001'\'';"'
```

**Checkpoint:** ¿qué sistema es fuente de verdad? ¿Qué dato depende de un
volumen y cuál depende de la memoria de un contenedor?

## CORE D — Sustitución de Pod y persistencia

Predice qué sucederá con el borrador antes de ejecutar:

```bash
kubectl delete pod orders-db-0
kubectl rollout status statefulset/orders-db --timeout=240s
kubectl get pods,pvc
```

Repite la consulta SQL de la fase anterior. Recoge evidencia del contenido del
registro y del PVC antes y después.

Si el Pod no vuelve a estar listo, consulta `kubectl describe pod orders-db-0`
y eventos; puede haber problemas de acceso al disco o scheduling. **No borres
el PVC para resolver esos errores**.

**Checkpoint:** ¿se ha recuperado un Pod con el mismo nombre? ¿Por qué el dato
sigue estando ahí? ¿Esto equivale a tener backups? (No.)

## CORE E — Provocar una caché obsoleta y repararla

En el seed inicial Redis conserva una representación temporal del borrador.
Compara Redis y PostgreSQL:

```bash
kubectl exec deployment/orders-cache -- redis-cli --raw GET order:ORD-DEMO-001
```

Actualiza **solo** PostgreSQL:

```bash
kubectl exec orders-db-0 -- sh -c \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -U orders -d ordersdb -v ON_ERROR_STOP=1 \
   -c "UPDATE course_order_drafts SET status = '\''CONFIRMED'\'' WHERE order_id = '\''ORD-DEMO-001'\'';"'
```

Consulta de nuevo Redis. Aunque PostgreSQL sea `CONFIRMED`, Redis aún mostrará
`CREATED`. Esto es un error de consistencia, no un fallo de red.

**Predicción:** ¿qué usuario vería el estado incorrecto si leyera únicamente la
caché? ¿Qué mecanismos permitirían evitarlo?

En esta simulación vamos a invalidar y reconstruir la clave:

```bash
kubectl exec deployment/orders-cache -- redis-cli DEL order:ORD-DEMO-001
kubectl exec deployment/orders-cache -- redis-cli SET order:ORD-DEMO-001 \
  '{"orderId":"ORD-DEMO-001","sku":"SKU-001","quantity":2,"status":"CONFIRMED"}'
kubectl exec deployment/orders-cache -- redis-cli --raw GET order:ORD-DEMO-001 | jq
```

Compara los estados finales de ambos almacenes. En una aplicación real,
la invalidación debe formar parte del flujo de escritura o de un protocolo
de consistencia bien definido; aquí la operación es **manual a propósito**.

## CORE F — Qué pasa si desaparece Redis

Antes del experimento, plantea una hipótesis sobre la pérdida de la clave:

```bash
kubectl delete pod -l app.kubernetes.io/name=orders-cache
kubectl rollout status deployment/orders-cache --timeout=180s
kubectl exec deployment/orders-cache -- redis-cli --raw GET order:ORD-DEMO-001
```

La clave debería desaparecer porque Redis se ejecuta sin persistencia.
La pérdida de caché **no debe destruir la fuente de verdad**.
Comprueba que el registro `CONFIRMED` permanece en PostgreSQL.

**Nota:** si la clave no desaparece, comprueba qué Pods Redis existían y si se
conectó a la misma instancia; registra la evidencia antes de concluir.

## Verificación y debrief

```bash
bash labs/p04-state-and-cache/scripts/verify.sh
```

La verificación espera que el estado del pedido de prueba sea `CONFIRMED` en
PostgreSQL; que Redis esté operativo es suficiente después del experimento de
pérdida de caché: **no se exige que una clave efímera exista**.

Explica con tus palabras:

1. ¿Por qué los Pods de Orders pueden ser reemplazables mientras que el
   volumen de PostgreSQL debe conservarse?
2. ¿Por qué StatefulSet no significa automáticamente alta disponibilidad?
3. ¿Qué diferencia hay entre guardar información en PostgreSQL y en Redis?
4. ¿Cómo se detecta una respuesta servida desde una caché desactualizada?
5. ¿Qué estrategias de invalidación compararías para una aplicación real?
6. ¿Qué cambios necesitaría Orders para usar estos almacenes a través de su API?

## SUPPORT — Comandos útiles

```bash
kubectl get pvc
kubectl describe pod orders-db-0
kubectl logs orders-db-0 --tail=40
kubectl describe deployment orders-cache
kubectl exec deployment/orders-cache -- redis-cli ping
kubectl get events --sort-by=.lastTimestamp | tail -n 20
```

Si ves un PVC `Pending`, revisa StorageClass, cuotas y permisos antes de
modificar el nombre del volumen o el StatefulSet.

## STRETCH — Elegir una política de caché

Define, sin desarrollarla, una política de consistencia para la vista de pedidos:
*cache-aside*, invalidación después de escritura, TTL, fallback a base de datos
cuando la caché falla y observabilidad de `cache hit/miss`. Justifica qué
inconsistencias aceptarías y cuáles no.

## Limpieza y seguridad

```bash
bash labs/p04-state-and-cache/scripts/cleanup.sh
```

La limpieza estándar elimina los workloads de P04 **pero conserva el PVC y el
Secret**, para evitar pérdida accidental de datos y permitir recuperar el
laboratorio. Consulta `scripts/cleanup.sh --help` antes de una limpieza definitiva.
No alteres los recursos de otros alumnos.
