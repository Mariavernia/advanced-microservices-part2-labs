# P06 — Service Mesh: identidad, mTLS y control de comunicaciones

**Modalidad:** individual desde Codespaces. **Prerequisitos:** P01 operativo, P05 protegido con Gateway 0.2.0-sec (rate limiting retirado), Orders e Inventory con inyección selectiva de Istio autorizada por el instructor. Sigue [la metodología de prácticas](../../docs/METODOLOGIA-PRACTICAS.md).

## Escenario

El equipo ha protegido el API Gateway con JWT. Ahora necesita migrar la comunicación interna a mTLS sin interrumpir las operaciones de pedidos. Un cliente legacy sin proxy todavía consume Inventory.

Tu misión: diseñar una política limitada al receptor correcto, demostrar qué comunicaciones permite o rechaza, diagnosticar un requisito de seguridad que no se está aplicando y evaluar una excepción de compatibilidad por puerto. No instalarás Istio ni cambiarás la seguridad de otros participantes.

## Preparación de plataforma (instructor)

El instructor mantiene Istio administrado de AKS y habilita la inyección persistente solo en las plantillas de Orders e Inventory. Debe confirmar que ambos Deployments tienen una réplica estable, los proxies están Ready, el Gateway sigue sin proxy y el preview de pedidos funciona. También comprueba capacidad, permisos de PeerAuthentication exclusivamente en tu namespace y ausencia de políticas temporales anteriores.

No etiquetes namespaces, no modifiques Istio global, no cambies ServiceAccounts compartidos ni elimines certificados. El alumno ya dispone de los permisos para gestionar su PeerAuthentication y sus Services; no necesita permisos administrativos.

## CORE 1 — Identifica el punto de partida

~~~bash
./scripts/preflight.sh
kubectl config view --minify -o jsonpath='{..namespace}'; echo
kubectl get deployment,pod,service
kubectl get peerauthentication
kubectl auth can-i create peerauthentications.security.istio.io
~~~

Si aparecen políticas anteriores o el instructor aún no ha confirmado la inyección, no continúes. Comprueba las plantillas, labels y los contenedores reales:

~~~bash
for APP in orders inventory api-gateway; do
  echo "=== $APP ==="
  kubectl get deploy "$APP" -o json | jq '{labels:.spec.template.metadata.labels,serviceAccount:.spec.template.spec.serviceAccountName}'
  kubectl get pods -l app.kubernetes.io/name="$APP" -o json |
    jq '.items[] | {pod:.metadata.name,containers:[.spec.containers[]?.name],init:[.spec.initContainers[]? | {name,restartPolicy}],proxyStatus:[.status.containerStatuses[]?,.status.initContainerStatuses[]? | select(.name=="istio-proxy") | {name,ready}]}'
done
~~~

Localiza Envoy en Orders e Inventory. En modo native sidecar puede estar en initContainers con restartPolicy Always. El Gateway no debe contenerlo. Identifica la revisión de inyección (por ejemplo, asm-1-31 en el entorno configurado) sin asumir que es idéntica en todas las instalaciones.

Dibuja ambos caminos y anota qué identidad se usa en cada uno:

- Usuario → Gateway → Orders → Inventory.
- Gateway sin Envoy → Inventory, por el Service interno.

El JWT del usuario no sustituye a los certificados de workload. Una cuenta de servicio default compartida no identifica de manera exclusiva a cada aplicación.

## CORE 2 — Construye tu banco de pruebas

Mantén las pruebas en tu namespace, con conexiones cortas y sin generar carga masiva. El contenedor Gateway dispone de curl. Utiliza el mismo endpoint de Inventory para comparar las dos identidades de transporte:

~~~bash
kubectl exec deploy/api-gateway -c api-gateway -- \
  curl -sS --max-time 8 -o /dev/null -w 'HTTP %{http_code}\n' \
  http://inventory:8080/actuator/health

kubectl exec deploy/orders -c orders -- \
  curl -sS --max-time 8 -o /dev/null -w 'HTTP %{http_code}\n' \
  http://inventory:8080/actuator/health
~~~

Antes de aplicar una política, ambos deben responder 200. Si uno falla, investiga primero DNS, endpoints, Pod Ready y NetworkPolicy (solo lectura). No atribuyas un fallo de baseline a mTLS.

Terminal A:

~~~bash
kubectl port-forward service/orders 8081:8080
~~~

Terminal B:

~~~bash
curl -fsS 'http://127.0.0.1:8081/api/orders/preview?sku=SKU-001&quantity=2' | jq
~~~

Confirma canBeFulfilled y los campos de instancia. Este port-forward es un acceso de diagnóstico al proceso Orders; lo que evaluamos es su llamada saliente hacia Inventory, no el cifrado del túnel del port-forward.

Crea una tabla de evidencia que completarás en cada fase:

| Estado de política | Gateway legacy → Inventory | Orders mesh → Inventory | Preview Orders | Evidencia de transporte |
|---|---|---|---|---|
| Baseline | | | | |
| PERMISSIVE | | | | |
| STRICT | | | | |
| Selector incorrecto | | | | |
| Excepción temporal | | | | |
| STRICT restaurado | | | | |
| Cierre | | | | |

Cada cambio puede tardar en propagarse desde el plano de control; repite las peticiones nuevas tras comprobar el recurso, sin confundir un retraso de propagación con el resultado estable.

## CORE 3 — Diseña la migración PERMISSIVE → STRICT

Copia la plantilla:

~~~bash
mkdir -p work/p06
cp labs/p06-service-mesh/templates/inventory-mtls.yaml work/p06/inventory-mtls.yaml
~~~

En el editor, sustituye el marcador del selector por la label **real** de los Pods Inventory. Mantén el nombre inventory-strict-mtls, no añadas namespace ni elimines el selector. No apliques políticas sin selector: afectarían a otros workloads de tu namespace.

Completa el fichero inicialmente con modo PERMISSIVE. Explica qué permite en el receptor y por qué puede ser útil durante la migración de clientes legacy.

~~~bash
kubectl get pods -l app.kubernetes.io/name=inventory --show-labels
kubectl apply --dry-run=server -f work/p06/inventory-mtls.yaml
kubectl apply -f work/p06/inventory-mtls.yaml
kubectl get peerauthentication inventory-strict-mtls -o yaml
~~~

Repite las dos llamadas de CORE 2. Después, cambia solo el modo a STRICT, predice qué camino se romperá y vuelve a aplicar **tu fichero**. No uses el manifiesto de recuperación como sustituto.

Repite el banco de pruebas. Esperamos que Orders → Inventory funcione y el Gateway legacy → Inventory sea rechazado. Un reset, timeout o HTTP 000 con curl no es un HTTP 403 de autorización. Registra el código y el error de transporte reales.

Comprueba que Orders sigue ofreciendo el preview y que Gateway sigue protegido con P05. La ruta Gateway → Inventory queda bloqueada durante STRICT; esto no implica que toda la aplicación esté caída. No ejecutes el verificador completo P01 mientras la política estricta bloquea esa ruta.

## CORE 4 — Demuestra mTLS y diagnostica una falsa sensación de seguridad

### A. Observa evidencia en Envoy

Antes y después de una nueva llamada desde Orders, consulta el proxy receptor:

~~~bash
kubectl exec deploy/inventory -c inventory -- \
  curl -fsS --max-time 8 http://127.0.0.1:15090/stats/prometheus | \
  grep '^istio_requests_total' | grep 'connection_security_policy="mutual_tls"' | \
  grep 'source_workload="orders"'
~~~

Compara el mismo conjunto de labels (incluido response_code) en ambas muestras. Un contador histórico mayor que cero no demuestra por sí solo que la última petición haya usado mTLS: busca el incremento al generar tráfico. Si la métrica no está disponible, no inventes un resultado; consulta al instructor. Distingue esta evidencia de la prueba funcional HTTP.

### B. Incidente: una política STRICT que no protege

El equipo afirma que basta con ver mode: STRICT en Kubernetes para garantizar que Inventory exige mTLS. Reproduce el error de despliegue: cambia en tu archivo de trabajo **solo el valor del selector** a una label inexistente, manteniendo STRICT. El selector debe ser no vacío. Aplica y espera la propagación.

Prueba el cliente legacy y el cliente mesh. Si el entorno heredado sigue en PERMISSIVE, el cliente sin Envoy vuelve a acceder aunque la política STRICT exista. Si el resultado no cambia, comprueba si hay otra política superior o un retraso de propagación.

Tu tarea es identificar qué recurso y qué Pods están seleccionados, demostrar por qué la política no afecta a Inventory y reparar tu propio fichero. No ejecutes delete ni reinicies toda la plataforma como primera opción.

Comprueba la recuperación con una prueba positiva y una negativa. Guarda el selector corregido y las evidencias. El dry-run del API valida estructura, pero no garantiza que el selector represente tu intención.

## CORE 5 — Control por puerto: requisito de compatibilidad temporal

Un equipo legacy solicita acceso durante la migración. La excepción debe ser explícita y limitada a la aplicación Inventory. Queremos distinguir el puerto publicado por un Service del puerto real del workload.

### A. Crea un Service auxiliar sin exponer Internet

Copia la plantilla y completa su selector, utilizando las labels de Inventory:

~~~bash
cp labs/p06-service-mesh/templates/inventory-alias.yaml work/p06/inventory-alias.yaml
kubectl apply --dry-run=server -f work/p06/inventory-alias.yaml
kubectl apply -f work/p06/inventory-alias.yaml
kubectl get svc inventory inventory-p06-alias -o yaml
kubectl get endpointslice -l kubernetes.io/service-name=inventory-p06-alias -o yaml
~~~

El Service auxiliar tiene port 18080 y targetPort 8080. Ambos Services seleccionan los mismos Pods y apuntan al mismo puerto de aplicación. No añade otra instancia de Inventory, ni LoadBalancer, ni NodePort.

Con STRICT todavía correcto, realiza una prueba directa desde el Gateway legacy al alias y otra desde Orders al mismo alias. Selecciona las URL tú mismo. Confirma que cambiar el puerto del Service no elimina la exigencia de mTLS en el receptor.

### B. Diseña la excepción

Consulta la referencia oficial de [PeerAuthentication](https://istio.io/latest/docs/reference/config/security/peer_authentication/). Añade a tu política STRICT una sección portLevelMtls. Debe contener el **puerto del workload**, no el puerto del Service, con modo PERMISSIVE. El resto de la política permanece STRICT.

Pista de estructura (completa los marcadores):

~~~yaml
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: REEMPLAZAR
  mtls:
    mode: STRICT
  portLevelMtls:
    REEMPLAZAR_PUERTO:
      mode: REEMPLAZAR_MODO
~~~

Aplica el archivo después de sustituir los marcadores. Comprueba que el puerto 8080 está asociado al Service original y al alias. Repite las dos llamadas a ambos Services. El cliente legacy debería recuperar acceso a Inventory y Orders debería seguir funcionando. PERMISSIVE admite mTLS y tráfico sin mTLS; no exige que los clientes con Envoy dejen de cifrar.

**Checkpoint:** ¿la excepción afecta exclusivamente al Service auxiliar o a cualquier Service que llegue a ese puerto del mismo workload? ¿Podemos permitir solo el Gateway legacy usando únicamente una excepción de puerto? Justifica la respuesta con los cuatro resultados y la política. No presentes este mecanismo como autorización por origen o por usuario.

### C. Retira la excepción y verifica

Elimina portLevelMtls de tu archivo y vuelve a aplicar la política. Si el campo persiste por la gestión declarativa, retíralo explícitamente del recurso de esta práctica:

~~~bash
kubectl patch peerauthentication inventory-strict-mtls --type=merge \
  -p '{"spec":{"portLevelMtls":null}}'
~~~

Confirma con get -o yaml que ya no existe la excepción. Repite la prueba legacy a ambos Services y la prueba mesh. Registra el estado STRICT recuperado.

## CORE 6 — Cierre seguro y continuidad

El objetivo era probar los controles, no dejar una política que bloquee el Gateway no mallado para las siguientes prácticas. Retira únicamente tus recursos temporales, incluso si algún experimento ha fallado:

~~~bash
kubectl delete peerauthentication inventory-strict-mtls --ignore-not-found
kubectl delete service inventory-p06-alias --ignore-not-found
kubectl get peerauthentication
kubectl get deployment orders inventory api-gateway
~~~

Repite el acceso directo Gateway → Inventory y el preview Orders. Deben volver a funcionar. Conserva la inyección selectiva en Orders e Inventory: P07 la necesita. No etiquetes ni des-etiquetes namespaces y no reapliques los Deployments de P01, porque perderías configuración de módulos anteriores.

Con el Gateway protegido y sin limitador activo, comprueba el acceso de P05 mediante sus peticiones individuales o su verificador, con tokens vigentes. Si el port-forward del Gateway se ha cerrado, vuelve a abrirlo.

## Evidencias que debes entregar

- Tu PeerAuthentication final de diseño STRICT y el manifiesto del Service auxiliar; conserva también la variante de excepción, sin credenciales.
- Tabla de los flujos HTTP antes y después de cada cambio y error de transporte cuando corresponda.
- Evidencia del selector erróneo, explicación y reparación.
- Muestras del contador mTLS de Envoy antes/después de una petición, o limitación constatada.
- Comparación de port y targetPort y explicación del alcance real de la excepción.
- Verificación de recuperación y ausencia de recursos temporales.

## SUPPORT — Diagnóstico y recuperación

| Síntoma | Qué comprobar |
|---|---|
| Proxy ausente o no Ready | Plantilla, revisión de inyección y estado de contenedores/initContainers; instructor |
| Ambos clientes fallan antes de STRICT | Service, EndpointSlice, DNS, disponibilidad de Inventory, NetworkPolicy |
| Legacy funciona tras STRICT | Selector real, modo, puerto, propagación, proxy receptor |
| Mesh falla tras STRICT | Proxy cliente/receptor, estado Ready, certificado y conectividad; instructor |
| HTTP 401/403 | JWT, audiencia y roles si atraviesas Gateway; no es evidencia automática de fallo mTLS |
| HTTP 000 / reset | Rechazo de transporte, timeout o red; correlaciona con baseline |
| Alias no tiene endpoints | Selector y labels, no modifiques los Pods para encajar un selector incorrecto |

~~~bash
kubectl describe pod -l app.kubernetes.io/name=inventory
kubectl logs deploy/inventory -c istio-proxy --tail=50
kubectl get peerauthentication inventory-strict-mtls -o yaml
kubectl get endpointslice -l kubernetes.io/service-name=inventory
~~~

Si la práctica bloquea el negocio, elimina solo inventory-strict-mtls e inventory-p06-alias. El instructor dispone del manifiesto de referencia y del procedimiento de recuperación de inyección. No borres políticas de aislamiento ni otros recursos de Istio.

## STRETCH — Identidad y autorización de workloads

Diseña una AuthorizationPolicy que limite el acceso a Inventory por identidad de servicio de Orders, con ServiceAccounts separados y mTLS. Explica por qué la cuenta default compartida no sirve para distinguirlos. No la apliques: los permisos de esta práctica no incluyen AuthorizationPolicy ni se han creado identidades dedicadas. Compara con segmentación NetworkPolicy, JWT y TLS externo.

**Límite de P06:** aquí configuramos autenticación de pares y control de comunicaciones por workload y puerto. El routing ponderado por VirtualService/DestinationRule y las políticas de autorización de workloads requieren una preparación adicional; no se han concedido esos permisos. El balanceo de versiones se experimenta en P03.

## Debrief

¿Qué controles del recorrido P05–P06 se complementan? ¿Qué riesgo implica mantener PERMISSIVE de forma permanente? ¿Qué evidencia demostraría cifrado en tránsito y qué evidencia sería necesaria para demostrar autorización de una identidad concreta? ¿Cómo migrarías el Gateway a la malla sin romper la API?
