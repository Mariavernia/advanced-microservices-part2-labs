# P04 — Estado persistente, almacenamiento y caché

**Modo:** individual, desde Codespaces. **Prerequisitos:** sesión autenticada, namespace personal, P01 operativo. Sigue [la metodología de prácticas](../../docs/METODOLOGIA-PRACTICAS.md).  
**Escenario:** Advanced Orders. **Rol:** ingeniero responsable de garantizar que un borrador de pedido sobreviva al reemplazo de un Pod, de gestionar escrituras concurrentes y de controlar los datos obsoletos en caché.

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
6. Detectar y evitar una actualización perdida con control optimista de versión.
7. Reproducir una carrera entre lectura, escritura e invalidación; decidir qué garantías puede ofrecer cache-aside.

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

### Tu espacio de trabajo

Para las siguientes operaciones usaremos una pequeña función de conexión, no un script que resuelva el ejercicio. Define estas funciones en una terminal Bash de Codespaces. Cada llamada SQL utiliza la contraseña ya configurada dentro del Pod; no se imprime ni se copia al entorno local. El cliente SQL lee la consulta por stdin y `-v ON_ERROR_STOP=1` hace visible un error.

~~~bash
p04_sql() {
  kubectl exec -i orders-db-0 -- sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -X -U orders -d ordersdb -v ON_ERROR_STOP=1 -At'
}
p04_redis() {
  kubectl exec deployment/orders-cache -- redis-cli --raw "$@"
}
~~~

Comprueba `p04_sql <<< 'SELECT 1;'` y `p04_redis PING`. Si cambias de terminal, vuelve a definir las funciones. No ejecutes el seed para recuperar una discrepancia: volvería a cambiar el dato que estás investigando.

## CORE D — Sustitución de Pod y persistencia

Predice qué sucederá con el borrador. Registra primero UID del Pod, UID y nombre del volumen asociado al PVC:

~~~bash
kubectl get pod orders-db-0 -o jsonpath='{.metadata.uid}'; echo
kubectl get pvc dbdata-orders-db-0 -o jsonpath='{.metadata.uid}{" "}{.spec.volumeName}'; echo
~~~

A continuación:

```bash
kubectl delete pod orders-db-0
kubectl rollout status statefulset/orders-db --timeout=240s
kubectl get pods,pvc
```

Repite la consulta SQL de la fase anterior. Recoge evidencia del contenido del
registro y del PVC antes y después. Repite los comandos de UID: el Pod conserva el nombre, pero debe tener otro UID; el PVC debe conservar UID y volumeName. No confundas identidad lógica del StatefulSet con identidad de una instancia.

Si el Pod no vuelve a estar listo, consulta `kubectl describe pod orders-db-0`
y eventos; puede haber problemas de acceso al disco o scheduling. **No borres
el PVC para resolver esos errores**.

**Checkpoint:** ¿se ha recuperado un Pod con el mismo nombre? ¿Por qué el dato
sigue estando ahí? ¿Esto equivale a tener backups? (No.)

## CORE E — Caché obsoleta: diseña la reconstrucción

El seed inicial deja una representación del borrador en Redis. Consulta los dos almacenes y la expiración:

~~~bash
p04_sql <<'SQL'
SELECT order_id, quantity, status FROM course_order_drafts
WHERE order_id = 'ORD-DEMO-001';
SQL
p04_redis GET order:ORD-DEMO-001 | jq
p04_redis TTL order:ORD-DEMO-001
~~~

Interpreta TTL = -1 (clave existente sin expiración) y -2 (clave inexistente). Antes de cambiar nada, predice qué sucede si la escritura en PostgreSQL no actualiza Redis.

**Tu tarea:** escribe una sentencia UPDATE que cambie solo el estado del borrador ORD-DEMO-001 a CONFIRMED. Usa WHERE para limitarla al pedido y RETURNING para demostrar qué fila cambió. No copies una orden de actualización general ni modifiques la caché todavía.

Puedes utilizar este punto de partida:

~~~sql
UPDATE course_order_drafts
SET status = /* valor objetivo */
WHERE /* identificador del pedido */
RETURNING order_id, quantity, status;
~~~

Ejecuta tu SQL con p04_sql (heredoc o fichero SQL desde stdin). Lee otra vez PostgreSQL y Redis. Conserva las dos evidencias: una vista está CONFIRMED y la otra puede seguir CREATED. Si no hay discrepancia, investiga el TTL y el estado del seed antes de concluir.

### Implementa cache-aside manualmente

En un diseño cache-aside, el consumidor intenta leer la caché; si no existe, consulta la fuente de verdad y repuebla la caché. Una escritura debe invalidar o actualizar la representación correspondiente.

1. Invalida **solo** la clave del pedido con DEL y comprueba que el siguiente GET no devuelve un documento.
2. Obtén el JSON de la fila real de PostgreSQL, en lugar de pegar una copia de datos con el estado escrito a mano. El esquema de JSON debe coincidir con el del seed: orderId, sku, quantity y status.
3. Reconstruye la clave a partir de ese JSON y elige un TTL de laboratorio. Usa un TTL entre 60 y 180 segundos para poder observarlo. Explica el compromiso entre frescura y consultas a la base de datos.
4. Lee Redis y compara todos los campos con la fila de PostgreSQL.

Consulta SQL de apoyo para la serialización, sin modificar datos:

~~~bash
ROW=$(p04_sql <<'SQL'
SELECT json_build_object('orderId',order_id,'sku',sku,
                         'quantity',quantity,'status',status)
FROM course_order_drafts WHERE order_id='ORD-DEMO-001';
SQL
)
printf '%s\n' "$ROW" | jq -e '.orderId=="ORD-DEMO-001" and .status=="CONFIRMED"'
~~~

Si la consulta no devuelve exactamente un documento válido, no repuebles la caché. Escribe tú el comando SET con el JSON de ROW y la opción EX; la sintaxis es `SET clave valor EX segundos`. Comprueba GET, TTL y el resultado de negocio. No cambies el valor de PostgreSQL para hacer coincidir dos resultados.

Observa la expiración con una segunda clave temporal que contenga el mismo JSON, utilizando EX 5. Consulta TTL y GET antes y después de que expire; elimina únicamente esa clave si aún existe. Distingue un cache miss por expiración de un dato incorrecto.

**Checkpoint:** presenta la fila SQL, el JSON obsoleto, el miss después de DEL, la reconstrucción correcta y el TTL observado. ¿El TTL evita servir información antigua durante su vigencia? ¿Quién debe realizar la consulta a la base de datos después de un miss?

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

## CORE G — Escrituras concurrentes y actualización perdida

Un pedido adicional recibe dos modificaciones de cantidad desde procesos diferentes. En lugar de aceptar cualquier escritura, el equipo necesita saber si otra operación modificó el pedido desde que se leyó.

Trabaja con el pedido **ORD-DEMO-002**. No alteres ORD-DEMO-001: su estado CONFIRMED es la evidencia del ejercicio anterior.

### G1 — Añade una versión al modelo de datos

La siguiente migración añade una versión inicial a los registros existentes. Se ejecuta una sola vez conceptualmente; IF NOT EXISTS permite repetirla sin duplicar la columna.

~~~bash
p04_sql <<'SQL'
ALTER TABLE course_order_drafts
ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1;
SQL
~~~

Crea tú el borrador ORD-DEMO-002 con SKU-001, status CREATED, versión 1 y una cantidad inicial positiva entre 1 y 5. Escribe el INSERT especificando las columnas. Para repetir **solo este experimento**, puedes eliminar previamente ese pedido y su clave Redis, nunca toda la tabla ni FLUSHALL. Comprueba la fila y anota su cantidad inicial.

~~~bash
p04_sql <<'SQL'
SELECT order_id, quantity, status, version FROM course_order_drafts
WHERE order_id='ORD-DEMO-002';
SQL
~~~

### G2 — Simula dos clientes

Dos clientes leen versión 1 y desean sumar una unidad a la cantidad. Ambos calculan su nueva cantidad a partir de la misma lectura. Haz la lectura dos veces y conserva los valores como A y B.

Predice el resultado si ambos realizan una actualización absoluta sin comprobar la versión. Para observar el problema, puedes hacer dos UPDATE consecutivos sobre ORD-DEMO-002 que establezcan la misma cantidad calculada. Comprueba que se pierde uno de los incrementos: se esperaban dos unidades adicionales y solo aparece una. Restaura la cantidad inicial y versión 1 de este pedido antes de continuar.

**Tu tarea:** completa una sentencia de actualización optimista con:

- Identificador del pedido y versión leída por el cliente en WHERE.
- Actualización de quantity y aumento de version en SET.
- RETURNING de quantity y version.

Plantilla (no ejecutable hasta completarla):

~~~sql
UPDATE course_order_drafts
SET quantity = /* nueva cantidad calculada */,
    version = /* siguiente versión */
WHERE order_id = /* pedido */
  AND version = /* versión que leyó el cliente */
RETURNING quantity, version;
~~~

Ejecuta como A la actualización basada en versión 1. Registra la fila devuelta y la nueva versión. Después ejecuta como B su operación basada todavía en versión 1. El segundo UPDATE debe afectar a cero filas: no es un error de SQL, es un conflicto de negocio. El comando psql puede indicar UPDATE 0; consulta también la fila final.

Resuelve el conflicto como B: relee la cantidad y versión actuales, recalcula la nueva cantidad y vuelve a intentar con la versión recién leída. Al final deben haberse aplicado los dos incrementos y version debe ser 3.

**Checkpoint:** muestra las tres operaciones (A, B obsoleta, B reintentada), los resultados y la cantidad final. Explica por qué una transacción no evita por sí sola una actualización perdida si la lógica usa un valor leído anteriormente. El control optimista detecta el conflicto; el consumidor decide si es seguro reintentar.

## CORE H — Reto de transferencia: la invalidación no basta

Ahora hay dos operaciones concurrentes entre PostgreSQL y Redis. Un lector A inicia un cache miss, consulta la base de datos y conserva la respuesta, pero todavía no la escribe en Redis. Un escritor B actualiza el pedido y ejecuta DEL. A termina tarde y vuelve a introducir la versión antigua en la caché.

Tu objetivo es reproducir esta carrera, identificar el dato obsoleto y proponer una solución que no confunda invalidación con consistencia fuerte.

### H1 — Reproduce la secuencia

Utiliza ORD-DEMO-002, que terminó CORE G en versión 3. Elimina únicamente su clave de caché si existe. Lee la fila real y guarda el JSON en una variable local `STALE`, usando el patrón json_build_object de CORE E **añadiendo el campo version**. Comprueba el JSON antes de continuar.

Como escritor B, suma una unidad a la cantidad actual y usa tu sentencia optimista con la versión actual. Confirma que PostgreSQL ha cambiado y que la versión aumenta. Invalida la clave Redis.

Como lector A, escribe ahora el JSON guardado en STALE con SET y EX 120. Compara Redis con PostgreSQL. El valor que acabas de guardar es antiguo, aunque B invalidó correctamente la clave. Registra ambas versiones y el TTL.

### H2 — Diagnostica y repara

No ejecutes seed-demo ni reinicies las bases de datos. Usa estas preguntas para decidir tu corrección:

- ¿Cuál es la fuente de verdad y qué operación llegó tarde?
- ¿Qué dato de la representación permite detectar que la caché es obsoleta?
- ¿Cómo reconstruyes la clave desde la versión actual sin perder los cambios de B?
- ¿Puede un TTL evitar esta carrera? ¿Qué ocurre si otra escritura obsoleta renueva la expiración?

**Resuelve tú el incidente:** identifica la clave, invalídala y reconstruye el JSON con la fila actual. Verifica que status, quantity y version coinciden. No dejes el dato antiguo como resultado final.

### H3 — Decide una política real

Documenta una política para cada tipo de lectura: una pantalla que admite cierto retraso y una operación de confirmación que exige el estado más reciente. Considera cache-aside con TTL, bypass de caché para operaciones críticas y control de versión. Describe cómo impedirías que una escritura antigua sobrescriba otra más nueva (por ejemplo, una comparación atómica de versiones en caché con una marca de invalidación conservada).

**Límite:** leer la versión de PostgreSQL antes de SET tampoco garantiza consistencia fuerte si otra escritura ocurre entre ambas operaciones. Redis y PostgreSQL no comparten una transacción atómica en este laboratorio. No presentes la reconstrucción manual ni un TTL como solución general al problema distribuido.

## Cierre del reto

Guarda tus sentencias SQL y un registro de las versiones observadas en tu fork (sin credenciales). Conserva la clave ORD-DEMO-002 reconstruida hasta ejecutar el verificador ampliado; después podrás eliminarla. Conserva los registros SQL y ORD-DEMO-001 CONFIRMED para las comprobaciones.

## Verificación y debrief

**Antes de `verify.sh`:** registra el resultado SQL antes/después de borrar el Pod PostgreSQL, la diferencia entre PostgreSQL y Redis durante la caché obsoleta y cómo la reparaste manualmente. Añade la evidencia de actualización perdida, conflicto optimista, reintento correcto y carrera de caché. Formula una política de invalidación; un `PASS` no sustituye esta evidencia.


```bash
bash labs/p04-state-and-cache/scripts/verify.sh
```

El verificador base conserva las comprobaciones originales. Para validar también el reto, ejecuta la comprobación ampliada **inmediatamente después de reconstruir la caché en CORE H**, con tu cantidad inicial de CORE G (no la cantidad final). Si ha expirado la clave, repuéblala desde la fila actual antes de verificarla.

~~~bash
# Sustituye 2 por la cantidad inicial que elegiste (1..5).
bash labs/p04-state-and-cache/scripts/verify.sh --extended 2
~~~

Esta comprobación exige que ORD-DEMO-002 tenga versión 4 y cantidad inicial + 3, y que el JSON actual de Redis coincida con PostgreSQL. No demuestra por sí sola los pasos intermedios: entrega también las evidencias de conflicto y carrera. Después puedes borrar únicamente la clave ORD-DEMO-002.

La verificación base espera que el estado del pedido de prueba sea `CONFIRMED` en
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

## STRETCH — Consistencia, replicación y fallos parciales

Diseña cómo publicar un evento de cambio de pedido desde PostgreSQL mediante un transactional outbox, invalidarlo de forma idempotente y recuperar un consumidor retrasado. Explica qué sucede si Redis no está disponible al confirmar una escritura. Compara esta solución con lectura de una réplica PostgreSQL asíncrona y con un almacén distribuido NoSQL: ¿qué significa leer un valor antiguo en cada caso? No despliegues clústeres adicionales ni supongas que un outbox garantiza consistencia fuerte. Define señales de cache hit/miss, lag y conflictos de versión.

## Limpieza y seguridad

```bash
bash labs/p04-state-and-cache/scripts/cleanup.sh
```

La limpieza estándar elimina los workloads de P04 **pero conserva el PVC y el
Secret**, para evitar pérdida accidental de datos y permitir recuperar el
laboratorio. Al utilizar `managed-csi`, un PVC persistente puede conservar un disco con costes asociados; el instructor decidirá cuándo eliminarlo de forma segura al finalizar el laboratorio. Consulta `scripts/cleanup.sh --help` antes de una limpieza definitiva.
No alteres los recursos de otros alumnos.
