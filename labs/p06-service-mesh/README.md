# P06 — De HTTP interno a mTLS entre microservicios con Istio

> **Estado:** borrador técnico para ensayo de instructor; **no liberado a alumnos**.  
> **Duración CORE objetivo:** 100–120 minutos, tras P05.  
> **Entorno:** fork personal + GitHub Codespaces; AKS del curso; sin instalación local.  
> **Regla:** no habilitar Istio en el clúster ni etiquetar namespaces desde la cuenta del alumno.

## Problema y decisión arquitectónica

En P05 protegimos el API Gateway con OAuth/OIDC y JWT. Eso **no protege necesariamente** las llamadas directas entre Orders e Inventory. Queremos demostrar la diferencia entre **identidad/autorización del usuario** (JWT en el Gateway), **identidad de carga de trabajo** (certificados de Istio) y **política de transporte** (mTLS STRICT).

Istio ya está instalado por el instructor como **AKS-managed Istio addon**, revisión `asm-1-31`. La inyección requiere la etiqueta de **namespace** `istio.io/rev=asm-1-31`; `istio-injection=enabled` no sirve en este addon. No se cambia el namespace de otros alumnos ni `security` ni `course-ingress`.

## Gate del instructor (antes de comenzar)

Esta práctica **no debe iniciarse** hasta que el instructor haya:

1. Validado en `student02` el consumo de recursos, el estado de P05 y el impacto en sus Pods.
2. Comprobado que los alumnos tienen permiso **limitado a su namespace** para leer/crear `PeerAuthentication`, y que no pueden aplicar políticas mesh-wide.
3. Etiquetado **solo** el namespace piloto con la revisión Istio, después de verificar el clúster y las cuotas.
4. Reiniciado primero Orders e Inventory bajo supervisión y comprobado que el contenedor `istio-proxy` está Ready en ambos; documentado un procedimiento de recuperación.
5. Verificado que una llamada funcional Orders → Inventory continúa operativa.

> Se utiliza `PeerAuthentication` con selector **solo Inventory**; no se modifica el modo mTLS de todo el clúster. Requiere validación real con alumno antes del uso general. Nunca ejecutar `kubectl label namespace` desde Codespaces de alumnos.

## CORE 1 — Predicción y observación de la malla

En el Codespace, tras `./scripts/preflight.sh` y con `kubectl` apuntando a **tu namespace**:

```bash
kubectl get pods -l app.kubernetes.io/name=orders
kubectl get pods -l app.kubernetes.io/name=inventory
kubectl get pods -l app.kubernetes.io/name=orders -o json \
  | jq -r '.items[].spec.containers[].name'
kubectl get pods -l app.kubernetes.io/name=inventory -o json \
  | jq -r '.items[].spec.containers[].name'
```

**Predije:** ¿qué contiene ahora cada Pod? ¿El Gateway JWT sustituye la identidad de trabajo? ¿Qué agrega Envoy respecto a una `NetworkPolicy`?

**Observé:** el Pod Orders y el Pod Inventory deberían tener aplicación + `istio-proxy`. Si no aparecen, no avances: avisa al instructor.

## CORE 2 — Camino funcional Orders → Inventory

Realiza port-forward al Service Orders (evitamos necesitar un token del Gateway para esta observación particular):

```bash
kubectl port-forward service/orders 8081:8080
```

En una **segunda terminal** de Codespaces:

```bash
curl -si 'http://127.0.0.1:8081/api/orders/preview?sku=SKU-001&quantity=2'
```

Anota HTTP status y evidencia `servedBy`/inventario. **No** presentes el port-forward como demostración de un cliente remoto con mTLS: el objetivo es demostrar que Orders, que sí tiene sidecar, puede contactar con Inventory.

## CORE 3 — ¿Qué significa PERMISSIVE frente a STRICT?

Prepara, con ayuda del instructor, un Pod temporal **sin sidecar** en el mismo namespace. Antes de aplicar STRICT, observa si puede invocar `http://inventory:8080`. El comportamiento concreto depende de la admisión, política de seguridad y versión del addon: documenta resultados, no asumas éxito.

Inspecciona el manifiesto `manifests/01-inventory-strict-mtls.yaml`: ¿qué workloads selecciona? ¿Por qué no tiene `namespace` fijo?

Cuando el instructor confirme que el cliente legacy funciona y el recurso está autorizado en tu namespace:

```bash
kubectl apply -f labs/p06-service-mesh/manifests/01-inventory-strict-mtls.yaml
kubectl get peerauthentication
kubectl describe peerauthentication inventory-strict-mtls
```

Predice si (a) Orders con sidecar y (b) un cliente sin sidecar podrán seguir llegando a Inventory. Repite las pruebas. El resultado buscado es:

- Orders → Inventory (ambos con sidecar): responde.
- Cliente legacy sin certificado → Inventory con STRICT: comunicación rechazada.

**No equiparar automáticamente HTTP 403 con un fallo mTLS:** el rechazo puede darse en la negociación de transporte y provocar reset/timeout, no una respuesta HTTP de aplicación.

## CORE 4 — Evidencia, reversión y límites

```bash
kubectl get peerauthentication inventory-strict-mtls -o yaml
kubectl get pods -l app.kubernetes.io/name=inventory -o wide
kubectl get pods -l app.kubernetes.io/name=orders -o wide
```

Explica qué se ha asegurado realmente y qué **no**: mTLS protege y autentica el canal entre proxies; no reemplaza la autorización por usuario de P05 ni corrige por sí solo vulnerabilidades en los servicios.

El instructor decidirá cuándo retirar la política. Comando de limpieza **solo de la política de esta práctica**:

```bash
kubectl delete -f labs/p06-service-mesh/manifests/01-inventory-strict-mtls.yaml --ignore-not-found
```

**No retires tú la etiqueta del namespace**, porque es un recurso compartido administrado por el instructor; no borres otros recursos Istio.

## SUPPORT — Diagnóstico

- Pod sin `istio-proxy`: comprobar si era existente y necesita `rollout restart`; solo instructor puede gestionar la etiqueta de namespace.
- Pod `Pending`: comprobar `kubectl describe pod`, cuotas y memoria; sidecar consume recursos.
- Pod `CrashLoopBackOff`: comprobar logs separando `-c istio-proxy` de contenedor Java.
- Error de acceso tras STRICT: diferenciar sidecar no inyectado, mTLS, `NetworkPolicy`, endpoint, JWT o service routing.
- Si una política mesh bloquea P01/P05, **retirar únicamente esta PeerAuthentication** y registrar el síntoma.

## STRETCH — Identidad de trabajo y autorización

Explorar `AuthorizationPolicy` sobre Inventory con una cuenta de servicio Kubernetes dedicada para Orders. **No aplicar hasta tener un manifiesto completo probado**, y no confundir un `ServiceAccount` compartido por todos los Pods con una identidad única de Orders.

## Evidencia mínima

- **Predije:** resultado esperado antes/después de STRICT.
- **Cambié:** qué PeerAuthentication y selector se aplicaron.
- **Observé:** dos flujos independientes y trazas de estado de Pods.
- **Concluyo:** qué aporta mTLS respecto a JWT, `NetworkPolicy` y TLS externo.

Fuentes:
- https://learn.microsoft.com/en-us/azure/aks/istio-deploy-addon
- https://istio.io/latest/docs/reference/config/security/peer_authentication/
- https://istio.io/latest/docs/tasks/security/authentication/mtls-migration/
