# P03 — Rolling deployment, rollback y CI

**Modo:** individual; el alumno manipula y diagnostica. **Prerequisito:** P01 operativo, preferiblemente tras P02. Sigue [la metodología de prácticas](../../docs/METODOLOGIA-PRACTICAS.md).
**Evidencia de salida:** reconstruir una secuencia de cambios, demostrar reversión y distinguir CI de CD.

## Escenario

El equipo debe entregar un cambio reversible sin permisos de administrador del clúster. Un Deployment puede aparecer Ready aunque el negocio falle por la configuración de Inventory.

## CORE 1 — Estado inicial y controles de CI

~~~bash
./scripts/preflight.sh
kubectl rollout status deployment/orders
kubectl rollout history deployment/orders
kubectl get deploy orders -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
~~~

Abre .github/workflows/test.yml. Identifica cómo se ejecutan Maven, Bash, validación YAML y checks al abrir un pull request en GitHub.

Ese workflow implementa **CI**. El despliegue remoto automatizado por alumno con OIDC es un paso adicional y no está habilitado todavía.

## CORE 2 — Revisión de configuración

**Antes de continuar:** apunta imagen, revisión, `APP_VERSION` y número de ReplicaSets. Predice cuáles cambiarán tras actualizar una variable de entorno del PodTemplate.

Vamos a crear una revisión visible mediante APP_VERSION. **Esto NO constituye la publicación de un nuevo binario ni una etiqueta de imagen distinta.**

~~~bash
kubectl set env deployment/orders APP_VERSION=0.2.0-lab
kubectl rollout status deployment/orders --timeout=180s
kubectl rollout history deployment/orders
kubectl get replicaset -l app.kubernetes.io/name=orders
~~~

Terminal A:

~~~bash
kubectl port-forward service/api-gateway 8080:8080
~~~

Terminal B:

~~~bash
curl -fsS 'http://localhost:8080/api/orders/preview?sku=SKU-001&quantity=2' | jq '{serviceVersion,servedBy}'
~~~

**Checkpoint obligatorio:** escribe la revisión anterior y la nueva, el ID del ReplicaSet nuevo, la imagen **antes/después** y el campo `serviceVersion` devuelto por HTTP. ¿Qué campo de PodTemplate ha cambiado? ¿Por qué hay una revisión nueva aunque el binario no cambiase?

## CORE 3 — Fallo real de la operación de negocio

Provoca un destino de Inventory inválido para Orders:

~~~bash
kubectl set env deployment/orders INVENTORY_BASE_URL=http://inventory-inexistente:8080
kubectl rollout status deployment/orders --timeout=180s
kubectl logs deployment/orders --tail=50
~~~

Repite el preview desde Terminal B (sin usar `curl -f` cuando necesites inspeccionar el cuerpo de una respuesta 5xx). **No ejecutes aún el rollback.** Obtén una evidencia de `rollout status`, otra del endpoint de negocio y otra de logs. ¿El fallo es de readiness o de la dependencia? ¿Qué evidencia apoya tu hipótesis? ¿Qué otra hipótesis descartas?

Recupera la revisión anterior:

~~~bash
kubectl rollout history deployment/orders
kubectl rollout undo deployment/orders
kubectl rollout status deployment/orders --timeout=180s
curl -fsS 'http://localhost:8080/api/orders/preview?sku=SKU-001&quantity=2' | jq
~~~

Un rollback deshace la última revisión; no lo ejecutes a ciegas si se han acumulado cambios. **Antes de ejecutarlo**, indica qué revisión deseas recuperar y por qué esa revisión fue buena. Verifica después la versión restaurada y comprueba ausencia de la URL inválida. Si no es la revisión esperada, investiga el historial antes de alterar más recursos.

### Observación importante: rollback operativo frente a estado declarativo

Una URL de Inventory inválida puede producir **HTTP 502** con código `INVENTORY_UNAVAILABLE` mientras `rollout status` devuelve éxito. Otros fallos de configuración pueden devolver 500. **Registra el estado HTTP real**, comprueba que el rollback elimina el override erróneo y verifica que el Gateway vuelve a responder 200.

Es posible que `kubectl rollout undo` advierta que no actualiza la anotación `kubectl.kubernetes.io/last-applied-configuration`. La revisión operativa se restaura, **pero eso no sincroniza el manifiesto versionado en Git ni la anotación del último `kubectl apply`**. Si luego ejecutas `kubectl apply` sobre un manifiesto antiguo de Orders, puedes alterar las probes o la variable APP_VERSION. Durante este laboratorio no vuelvas a aplicar a ciegas el YAML antiguo de P01: inspecciona antes `kubectl get deployment orders -o yaml` y prepara una definición declarativa coherente con el estado deseado.

## CORE 4 — Diseña gates de una entrega real

Documenta qué comprobarías para promover la revisión: tests de servicio, validación de manifiestos, resultados de observabilidad y prueba funcional. ¿Qué señales justificarían rollback automático?

El pipeline de tests está implementado, pero **el CD automático desde los forks mediante credenciales GitHub OIDC no forma parte de esta práctica**. No deben guardarse kubeconfigs administrativos ni credenciales compartidas en los forks.

## SUPPORT

~~~bash
kubectl describe deployment orders
kubectl rollout history deployment/orders
kubectl get pods -l app.kubernetes.io/name=orders
kubectl get events --sort-by=.lastTimestamp | tail -n 25
~~~

## STRETCH

Compara Rolling, Blue/Green y Canary desde tres ejes: riesgo de negocio, operabilidad y coste. Propón umbrales mensurables de errores/latencia para promover un canary.

## Evidencia mínima y debrief

Entrega cuatro frases — **predije, cambié, observé, concluyo** — con revisión inicial/final y el resultado HTTP antes/durante/después de la avería. El ejercicio no se considera superado únicamente porque `rollout status` diga `successfully rolled out`.

## Debrief

1. ¿Por qué un rollout verde puede ofrecer una API rota?
2. ¿Qué evidencias deben acompañar la orden de rollback?
3. ¿Qué principio de mínimo privilegio debe cumplir un futuro CD desde forks?
4. ¿Cómo evitarías que un alumno modifique recursos del compañero?

