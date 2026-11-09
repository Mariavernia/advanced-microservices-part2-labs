# P03 — Rolling deployment, rollback y CI

**Modo:** individual. **Prerequisito:** P01 operativo, preferiblemente tras P02.
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

Checkpoint: ¿qué campo de PodTemplate ha cambiado? ¿Por qué Kubernetes creó una revisión aunque la imagen de contenedor no cambió?

## CORE 3 — Fallo real de la operación de negocio

Provoca un destino de Inventory inválido para Orders:

~~~bash
kubectl set env deployment/orders INVENTORY_BASE_URL=http://inventory-inexistente:8080
kubectl rollout status deployment/orders --timeout=180s
kubectl logs deployment/orders --tail=50
~~~

Repite el preview desde Terminal B. Observa tanto estado de pods como respuesta HTTP. ¿El fallo es de readiness o de la dependencia? ¿Qué evidence apoya tu hipótesis?

Recupera la revisión anterior:

~~~bash
kubectl rollout history deployment/orders
kubectl rollout undo deployment/orders
kubectl rollout status deployment/orders --timeout=180s
curl -fsS 'http://localhost:8080/api/orders/preview?sku=SKU-001&quantity=2' | jq
~~~

Un rollback deshace la última revisión; no lo ejecutes a ciegas si se han acumulado cambios. Verifica la versión restaurada y comprueba ausencia de la URL inválida.

## CORE 4 — Diseña gates de una entrega real

Documenta qué comprobarías para promover la revisión: tests de servicio, validación de manifiestos, resultados de observabilidad y prueba funcional. ¿Qué señales justificarían rollback automático?

El pipeline de tests está implementado, pero **el CD automático por forks y credenciales GitHub OIDC de mínimo privilegio está pendiente**. No deben guardarse kubeconfigs administrativos ni credenciales compartidas en los forks.

## SUPPORT

~~~bash
kubectl describe deployment orders
kubectl rollout history deployment/orders
kubectl get pods -l app.kubernetes.io/name=orders
kubectl get events --sort-by=.lastTimestamp | tail -n 25
~~~

## STRETCH

Compara Rolling, Blue/Green y Canary desde tres ejes: riesgo de negocio, operabilidad y coste. Propón umbrales mensurables de errores/latencia para promover un canary.

## Debrief

1. ¿Por qué un rollout verde puede ofrecer una API rota?
2. ¿Qué evidencias deben acompañar la orden de rollback?
3. ¿Qué principio de mínimo privilegio debe cumplir un futuro CD desde forks?
4. ¿Cómo evitarías que un alumno modifique recursos del compañero?

**Estado del laboratorio:** preparado en Git; requiere prueba real de rollout y rollback con una cuenta de alumno.
