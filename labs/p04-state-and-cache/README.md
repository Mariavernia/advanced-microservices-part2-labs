# P04 — Estado persistente, almacenamiento y caché

**Modo:** individual, desde Codespaces. **Prerequisitos:** sesión autenticada, namespace personal, P01 operativo. Sigue [la metodología de prácticas](../../docs/METODOLOGIA-PRACTICAS.md).  
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

## CORE B — Desplegar almacenamiento aislado, por etapas

**Ruta de trabajo del alumno:** la base de datos y la caché se despliegan **por separado**, inspeccionando los manifiestos y el comportamiento de cada controlador. No comiences ejecutando `scripts/deploy.sh`: ese helper despliega ambos componentes de una vez y queda reservado para la preparación rápida o recuperación del instructor. El helper `prepare-demo-password.sh` sí se utiliza: genera únicamente una contraseña sintética aleatoria sin mostrarla ni guardarla en Git.

### B1 — Antes de crear la base de datos

Abre `manifests/01-orders-db.yaml`. Predice:
- ¿Qué nombres recibirán el StatefulSet, el Pod y el PVC?
- ¿Cuál es el propósito de `clusterIP: None`? ¿Qué diferencia existe respecto al Service normal de Redis?
- ¿Qué aportan `volumeClaimTemplates`, `accessModes: ReadWriteOnce` y `storageClassName: managed-csi`?
- ¿Qué debería ocurrir con el PVC cuando reemplazas el Pod, sin eliminar el StatefulSet?

Comprueba el namespace y los permisos relevantes; **no necesitas permisos de administración del clúster**:

```bash
./scripts/preflight.sh
kubectl config view --minify -o jsonpath='{..namespace}'; echo
kubectl auth can-i create statefulsets
kubectl auth can-i create persistentvolumeclaims
kubectl get statefulsets,pvc
```

### B2 — Preparar la credencial sintética y desplegar PostgreSQL

```bash
bash labs/p04-state-and-cache/scripts/prepare-demo-password.sh
kubectl apply -f labs/p04-state-and-cache/manifests/01-orders-db.yaml
kubectl rollout status statefulset/orders-db --timeout=240s
kubectl get statefulset,pods,pvc,services
kubectl describe pvc dbdata-orders-db-0
```

**Checkpoint:** el alumno identifica la relación StatefulSet `orders-db` → Pod `orders-db-0` → PVC `dbdata-orders-db-0`. Un PVC `Bound` es una evidencia de almacenamiento asociado, **no equivale a backup**. Si queda en `Pending`, no lo borres: revisa sus eventos y avisa al instructor.

 
**Seguridad del contenedor:** el StatefulSet usa `runAsNonRoot=true`, UID/GID `70` del usuario `postgres` de la imagen Alpine, `fsGroup=70` para permisos del Azure Disk, `seccompProfile=RuntimeDefault`, `allowPrivilegeEscalation=false` y `capabilities.drop=[ALL]`. Antes de desplegar, identifica estos campos y razona por qué PostgreSQL necesita escribir en el volumen incluso cuando no se ejecuta como root. Si un manifiesto anterior mostraba `would violate PodSecurity "restricted:latest"`, actualiza el fork del curso y reaplica la definición endurecida (sin borrar StatefulSet ni PVC). Comprueba:

```bash
kubectl exec orders-db-0 -- id
kubectl exec orders-db-0 -- sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_isready -U orders -d ordersdb'
kubectl get pod orders-db-0 -o jsonpath='{.spec.securityContext}'; echo
```

Un Pod `1/1 Ready` con almacenamiento `Bound` confirma que la configuración funciona; **no implica todavía que hayamos demostrado persistencia** (eso se comprobará al escribir datos y borrar/recrear el Pod en CORE D).

`StorageClass` es un recurso de ámbito de clúster y el rol limitado del alumno puede impedir ejecutar `kubectl get storageclass`. **No amplíes permisos del alumno para resolverlo**. El instructor puede comprobar las StorageClasses con su identidad administrativa si el PVC no se aprovisiona.

### B3 — Desplegar Redis y comparar arquitecturas

Abre `manifests/02-orders-cache.yaml`. Compara el Deployment de Redis con el StatefulSet de PostgreSQL. Localiza la configuración que desactiva snapshots RDB y AOF; no confundas esta demo con un diseño de caché de producción.

```bash
kubectl apply -f labs/p04-state-and-cache/manifests/02-orders-cache.yaml
kubectl rollout status deployment/orders-cache --timeout=180s
kubectl get deployments,statefulsets,pods,services,pvc
kubectl exec deployment/orders-cache -- redis-cli ping
```

**Checkpoint:** Redis utiliza UID 999/GID 1000 de la imagen Alpine y el mismo baseline `restricted` de capacidades/seccomp/no escalada. Comprueba con `kubectl exec deployment/orders-cache -- id`. ¿Qué componente depende de un PVC? ¿Cuál depende de la memoria del contenedor? ¿Qué riesgos de pérdida de estado tiene cada uno? **No ejecutes todavía `seed-demo.sh` ni el verificador**; primero hay que comprender dónde vivirán los datos.

## CORE C — Un borrador en PostgreSQL

El helper `seed-demo.sh` prepara los datos del escenario; **no resuelve el ejercicio de consistencia ni demuestra persistencia**. El siguiente comando crea una tabla de prácticas y un borrador idempotente
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

**Antes de `verify.sh`:** registra el resultado SQL antes/después de borrar el Pod PostgreSQL, la diferencia entre PostgreSQL y Redis durante la caché obsoleta y cómo la reparaste manualmente. Formula una política de invalidación; un `PASS` no sustituye esta evidencia.


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
laboratorio. Al utilizar `managed-csi`, un PVC persistente puede conservar un disco con costes asociados; el instructor decidirá cuándo eliminarlo de forma segura al finalizar el laboratorio. Consulta `scripts/cleanup.sh --help` antes de una limpieza definitiva.
No alteres los recursos de otros alumnos.
