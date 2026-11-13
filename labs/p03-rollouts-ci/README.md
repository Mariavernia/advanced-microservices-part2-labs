# P03 — Entrega continua y estrategias de despliegue

**Modo:** individual, desde tu fork y Codespaces. **Prerequisito:** P01 operativo; P02 recuperado y con una sola réplica de Orders, sin Job de carga ni política temporal de alta disponibilidad. Sigue [la metodología de prácticas](../../docs/METODOLOGIA-PRACTICAS.md).

## Escenario

Advanced Orders necesita entregar un cambio de configuración de forma verificable y reversible. Tu trabajo consiste en construir una puerta de calidad (quality gate), detectar una entrega inválida antes de desplegarla, promover el cambio aprobado y demostrar que una revisión técnicamente saludable puede fallar en negocio.

No necesitas escribir una aplicación Java desde cero ni obtener permisos de escritura en ACR. Utilizamos el binario Orders ya publicado. Las nuevas revisiones de esta práctica son cambios de configuración, no binarios nuevos. GitHub Actions realiza CI; la promoción a AKS se ejecuta manualmente desde tu sesión Entra, como un paso de entrega controlada. **No es CD automático**.

## Entregables

- PR de tu fork con dos ejecuciones CI: una fallida por la política de entrega y otra corregida, ambas con evidencia.
- Patch de release y un nuevo paso del workflow que comprueba el contrato.
- Historial de rollout con revisión saludable, revisión fallida y recuperación explícita, evidencia HTTP y logs.
- Evidencia de Blue/Green: prueba de candidato, cambio de tráfico y reversión. Una comparación con Canary y sus límites.

## CORE 1 — Prepara una entrega en tu fork

Esta fase no necesita que AKS esté encendido. Comprueba que el remoto origin apunta a **tu fork**, no al repositorio de origen.

~~~bash
git status -sb
git remote -v
git branch --show-current
~~~

Si tienes cambios locales de P01/P02, guárdalos en tu rama de trabajo antes de continuar. Parte de main actualizado de tu fork, sin descartar tus cambios. Comprueba en GitHub que Actions está habilitado para tu fork y que dispones de cuota. El instructor puede ayudarte si la política de GitHub de tu cuenta no permite ejecutar workflows.

~~~bash
git switch main
git pull --ff-only origin main
git switch -c p03-release
mkdir -p work/p03
cp labs/p03-rollouts-ci/templates/orders-release.patch.json work/p03/orders-release.patch.json
~~~

Abre el patch de trabajo. Localiza APP_VERSION e INVENTORY_BASE_URL. La propuesta de entrega contiene **un defecto de configuración deliberado**. No lo corrijas todavía ni lo apliques a AKS.

Abre .github/workflows/test.yml. Localiza triggers, permisos, checkout, Maven y validación de manifiestos. Responde: ¿qué verifica cada paso y qué defecto de configuración de negocio podría escapar a la compilación y a un parser YAML?

## CORE 2 — Construye el quality gate y haz fallar CI

El contrato de release exige cambiar únicamente las dos variables autorizadas de Orders, usar una versión de configuración X.Y.Z-lab y resolver Inventory mediante su Service interno en el puerto 8080.

El helper `labs/p03-rollouts-ci/scripts/check-release.py` implementa esa política estática. Léelo y relaciona sus condiciones con el contrato. No instala software, no despliega y no necesita secretos.

Tu tarea es **editar el workflow existente** para añadir un paso al job build-test, después de los controles existentes. Usa como referencia la estructura de los pasos anteriores:

~~~yaml
      - name: P03 release policy
        run: # TODO: invoca Python con el validador y TU patch de trabajo
~~~

Completa run con una llamada a python3, el path del helper y el archivo work/p03/orders-release.patch.json. No modifiques el helper para hacer que acepte el defecto. Conserva todos los demás checks y permissions: contents: read. No añadas credenciales Azure ni kubeconfigs.

Comprueba en el editor que la indentación es correcta. Revisa y sube **solo** los dos archivos:

~~~bash
git diff -- .github/workflows/test.yml
git add .github/workflows/test.yml work/p03/orders-release.patch.json
git diff --cached
git commit -m "Add release policy gate and candidate configuration"
git push -u origin p03-release
~~~

Si GitHub rechaza el push por falta de permiso para modificar workflows, no desactives los controles. Comprueba la autorización de tu cuenta GitHub y solicita ayuda al instructor. Como alternativa, edita el workflow desde la interfaz web de tu fork, en la misma rama, y sincroniza tu Codespace antes de continuar. No compartas tokens personales.

En GitHub abre un pull request **dentro de tu fork**: base repository = tu fork, base = main, head = p03-release de tu fork. La interfaz puede ofrecer por defecto el repositorio de origen: cámbialo antes de crear el PR. No abras PR hacia el repositorio del curso.

En Checks / Actions abre la ejecución y localiza el job build-test y el paso P03 release policy. Si el workflow falla antes de llegar a tu paso, diagnostica primero ese fallo. Si no se inicia, comprueba Actions habilitado y que el PR apunta a tu fork.

**Checkpoint rojo:** registra el SHA de la rama, URL de la ejecución, paso que falló y mensaje de la política. ¿Por qué el resto de tests puede pasar si el destino de Inventory es incorrecto?

## CORE 3 — Corrige y demuestra CI verde

A partir del mensaje de fallo, inspecciona el contrato de Inventory en P01. Corrige el valor erróneo en tu patch y mantén el resto. Ejecuta localmente el comando que has añadido al workflow.

~~~bash
git diff -- work/p03/orders-release.patch.json
git add work/p03/orders-release.patch.json
git commit -m "Repair release configuration"
git push
~~~

El mismo PR debe disparar una ejecución nueva. Comprueba que llega al paso de política y que **todos** los checks pasan. Anota el SHA aprobado; no basta una captura verde de otro commit.

Si no puedes ejecutar Actions por cuota o política de la cuenta, realiza la comprobación local con el mismo comando y Maven, registra esa limitación y solicita una demostración del instructor. La ejecución local no equivale a CI remoto.

**No fusiones ni despliegues una entrega roja.** Puedes mantener el PR abierto para conservar las evidencias. En el siguiente paso desplegarás exactamente el patch aprobado de tu rama.

## CORE 4 — Promoción controlada y rolling update

A partir de aquí se requiere AKS encendido. Confirma tu identidad y namespace.

~~~bash
./scripts/preflight.sh
bash labs/p01-complete-platform/scripts/verify.sh
kubectl rollout status deployment/orders
kubectl rollout history deployment/orders
kubectl get deployment orders -o json | jq '{replicas:.spec.replicas, strategy:.spec.strategy, image:.spec.template.spec.containers[0].image, env:.spec.template.spec.containers[0].env}'
kubectl get hpa orders --ignore-not-found
~~~

Si queda HPA o una escala distinta de 1, termina la recuperación de P02 según su README (no borres otros recursos). Asegúrate de que P06/P07 aún no se han aplicado. Esta práctica no modifica sus configuraciones.

Apunta revisión inicial, imagen, APP_VERSION, probes y ReplicaSets. Predice cuáles cambiarán con el patch aprobado. Comprueba que el archivo de trabajo coincide con el commit verde:

~~~bash
git status --short
git log -1 --oneline
python3 labs/p03-rollouts-ci/scripts/check-release.py work/p03/orders-release.patch.json
kubectl patch deployment orders --type=strategic --patch-file work/p03/orders-release.patch.json --dry-run=server -o yaml
~~~

Si no coincide el commit aprobado, no promociones. Puedes comparar el fichero con la versión exacta del SHA verde usando git show y cmp. Aplica tu patch:

~~~bash
kubectl patch deployment orders --type=strategic --patch-file work/p03/orders-release.patch.json
kubectl rollout status deployment/orders --timeout=300s
kubectl rollout history deployment/orders
kubectl get replicaset -l app.kubernetes.io/name=orders
~~~

Terminal A (si no tienes ya un port-forward activo de P01):

~~~bash
kubectl port-forward service/api-gateway 8080:8080
~~~

Terminal B:

~~~bash
curl -fsS 'http://localhost:8080/api/orders/preview?sku=SKU-001&quantity=2' | jq '{serviceVersion,servedBy,canBeFulfilled}'
~~~

**Checkpoint:** anota revisión nueva y ReplicaSet, imagen antes/después, versión y resultado de negocio. El patch no cambia la imagen ni las probes de P02. Registra el número de revisión que funciona (no lo deduzcas del ejemplo):

~~~bash
GOOD_REVISION=$(kubectl get deployment orders -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}')
echo "$GOOD_REVISION"
~~~

## CORE 5 — Una revisión verde en Kubernetes, pero rota en negocio

El equipo quiere comprobar si readiness protege frente a una dependencia mal configurada. Este experimento simula un cambio imperativo que **evita el gate**. No subas ni apruebes ese cambio.

1. Copia tu patch aprobado a un fichero temporal local y modifica únicamente INVENTORY_BASE_URL con un nombre de Service que no exista en tu namespace.
2. Aplica el fichero temporal con patch estratégico. No edites la configuración de un compañero.
3. Observa el rollout, los Pods y las sondas. Repite el preview sin curl -f para ver el código HTTP y el cuerpo de error.

~~~bash
cp work/p03/orders-release.patch.json /tmp/p03-fault.patch.json
# Edita /tmp/p03-fault.patch.json antes de ejecutar:
kubectl patch deployment orders --type=strategic --patch-file /tmp/p03-fault.patch.json
kubectl rollout status deployment/orders --timeout=300s
kubectl logs deployment/orders --tail=60
curl -si 'http://localhost:8080/api/orders/preview?sku=SKU-001&quantity=2'
~~~

**Diagnóstico:** formula dos hipótesis y obtén evidencia. ¿Es problema de scheduling, readiness, DNS/Service o aplicación? Comprueba la variable que usa Orders, el Service Inventory y sus endpoints. ¿Por qué el gate de CI habría detectado este defecto, pero las sondas no necesariamente?

Recupera la revisión identificada, no una revisión al azar:

~~~bash
kubectl rollout history deployment/orders
kubectl rollout undo deployment/orders --to-revision="$GOOD_REVISION"
kubectl rollout status deployment/orders --timeout=300s
curl -fsS 'http://localhost:8080/api/orders/preview?sku=SKU-001&quantity=2' | jq '{serviceVersion,canBeFulfilled,servedBy}'
rm -f /tmp/p03-fault.patch.json
~~~

Si la variable GOOD_REVISION se ha perdido, identifica la revisión correcta con rollout history --revision antes de recuperar. Comprueba que el valor INVENTORY_BASE_URL vuelve al destino correcto. El rollback recupera una plantilla de Pod; no reescribe Git ni el historial declarativo del último apply. Tu patch aprobado sigue siendo la fuente de configuración de esta entrega.

## CORE 6 — Blue/Green: probar antes de cambiar el tráfico

Rolling cambia instancias dentro de un Deployment. Blue/Green mantiene dos conjuntos separados. Vamos a usar un candidato aislado que ejecuta el mismo binario con otra versión de configuración. El instructor confirma capacidad para un Pod adicional.

Inspecciona [el manifiesto del candidato](manifests/01-orders-green.yaml): Deployment, Service, selectors, probes y APP_VERSION. Copia a tu directorio de trabajo y **elige una marca de versión distinta a la estable**, conservando el sufijo green. No cambies la imagen ni el selector de los Deployments.

~~~bash
cp labs/p03-rollouts-ci/manifests/01-orders-green.yaml work/p03/orders-green.yaml
# Edita APP_VERSION en tu copia.
kubectl apply --dry-run=server -f work/p03/orders-green.yaml
kubectl apply -f work/p03/orders-green.yaml
kubectl rollout status deployment/orders-green --timeout=300s
kubectl get services orders orders-green
kubectl get endpointslice -l kubernetes.io/service-name=orders
kubectl get endpointslice -l kubernetes.io/service-name=orders-green
~~~

Comprueba que el Service estable no selecciona el candidato. Desde Gateway, prueba Green directamente antes de promoverlo:

~~~bash
kubectl exec deploy/api-gateway -c api-gateway -- curl -fsS 'http://orders-green:8080/api/orders/preview?sku=SKU-001&quantity=2' | jq '{serviceVersion,servedBy,canBeFulfilled}'
curl -fsS 'http://localhost:8080/api/orders/preview?sku=SKU-001&quantity=2' | jq '{serviceVersion,servedBy,canBeFulfilled}'
~~~

Elige qué observaciones serían suficientes para autorizar el cambio (salud, contrato de negocio, configuración, métricas). Registra la versión estable y la candidata.

**Tu decisión de routing:** modifica exclusivamente el selector del Service orders para que seleccione Green. Completa el valor del patch a partir de las labels del candidato:

~~~bash
kubectl get service orders -o json | jq '.spec.selector'
kubectl get deployment orders-green -o json | jq '.spec.template.metadata.labels'
# Sustituye el marcador por el valor real antes de ejecutar:
kubectl patch service orders --type=json -p='[{"op":"replace","path":"/spec/selector","value":{"app.kubernetes.io/name":"REEMPLAZAR"}}]'
kubectl get endpointslice -l kubernetes.io/service-name=orders -o wide
curl -fsS 'http://localhost:8080/api/orders/preview?sku=SKU-001&quantity=2' | jq '{serviceVersion,servedBy,canBeFulfilled}'
~~~

Espera que el EndpointSlice refleje los endpoints candidatos. Las conexiones existentes pueden seguir reutilizándose; verifica nuevas conexiones y el resultado de negocio. No elimines el Deployment estable: es tu camino de retorno.

**Reversión:** restaura el selector original (app.kubernetes.io/name: orders), comprueba los endpoints y demuestra la versión estable. Esta reversión de tráfico es distinta de rollout undo.

~~~bash
kubectl patch service orders --type=json -p='[{"op":"replace","path":"/spec/selector","value":{"app.kubernetes.io/name":"orders"}}]'
kubectl get endpointslice -l kubernetes.io/service-name=orders
curl -fsS 'http://localhost:8080/api/orders/preview?sku=SKU-001&quantity=2' | jq '{serviceVersion,servedBy,canBeFulfilled}'
~~~

No borres Green hasta verificar el retorno estable. Si falla el routing, restaura el selector original antes de investigar más.

## STRETCH — Canary por conjunto de endpoints

Realiza esta ampliación solo con autorización del instructor y antes de eliminar Green. Un Service Kubernetes no ofrece ponderaciones de tráfico exactas ni promoción automática: este experimento muestra selección simultánea, no un canary de producción.

Añade a la plantilla del Deployment estable la label compartida que ya tiene Green (training.release-group: orders). Utiliza un patch estratégico de metadata de la plantilla, sin alterar el selector inmutable del Deployment. Espera el rollout.

Después, cambia el selector del Service orders a esa label compartida con un patch JSON replace. Predice cuántos endpoints habrá y verifica el resultado.

Desde el Gateway, ejecuta varias peticiones directas al Service orders con conexiones nuevas y agrupa serviceVersion:

~~~bash
for i in $(seq 1 20); do
  kubectl exec deploy/api-gateway -c api-gateway -- curl -fsS 'http://orders:8080/api/orders/preview?sku=SKU-001&quantity=2' | jq -r '.serviceVersion'
done | sort | uniq -c
~~~

No esperes un porcentaje exacto ni deduzcas garantías de distribución con una muestra pequeña. Explica cómo implementarías un canary ponderado con Gateway API o una malla, qué señales usarías para promover o revertir y qué pasaría con conexiones persistentes.

Restaura el selector estable y elimina la label temporal de su plantilla, conservando la configuración de release. Verifica rollout y endpoints antes del cierre.

## Cierre y evidencias

Incluso si no realizaste STRETCH, garantiza que Orders vuelve a seleccionar solo su Deployment estable:

~~~bash
kubectl patch service orders --type=json -p='[{"op":"replace","path":"/spec/selector","value":{"app.kubernetes.io/name":"orders"}}]'
kubectl delete -f work/p03/orders-green.yaml --ignore-not-found
kubectl rollout status deployment/orders --timeout=300s
bash labs/p01-complete-platform/scripts/verify.sh
~~~

Si no llegaste a crear el candidato, omite su delete. Conserva las probes y la configuración aprobada de Orders; no reapliques el Deployment antiguo de P01. Elimina solo recursos temporales de P03. Guarda tus cambios y evidencias sin credenciales.

| Evidencia | Qué debes mostrar |
|---|---|
| CI | Dos ejecuciones del mismo PR, SHA y paso rojo/verde; explicación del defecto |
| Rolling | Imagen invariable, revisión y resultado HTTP |
| Recuperación | Fallo de negocio, hipótesis, logs, revisión seleccionada y respuesta recuperada |
| Blue/Green | Selectors y EndpointSlices antes/después, versiones observadas y reversión |
| Decisión | Qué gate añadirías para promover automáticamente con seguridad |

**Debrief:** distingue CI, entrega controlada y despliegue continuo. Explica por qué un pipeline verde no garantiza una operación saludable, por qué readiness no sustituye un smoke test de negocio y qué identidad de mínimo privilegio necesitaría un futuro CD automatizado. No se concede acceso administrativo ni se configuran credenciales de despliegue en los forks.
