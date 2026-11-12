# P00 — Kubernetes Survival Kit

**Mode:** individual  
**Platform:** Advanced Orders Platform — Orders + Inventory
**Method:** [Student lab methodology](../../docs/METODOLOGIA-PRACTICAS.md). Apply resources and investigate them yourself; run `verify.sh` only at the end.

## Scenario

You have joined the team responsible for **Advanced Orders Platform**.

The first two services are ready to run on Kubernetes:

```text
Client → Orders → Inventory
```

The application images have already been built. Your task is not to develop the services in this lab. You will deploy them, observe how Kubernetes keeps them running, and verify how Orders finds Inventory without knowing a Pod IP.

Your course login has already selected your personal Kubernetes namespace. Unless explicitly requested, do not add a namespace to the manifests.

---

## What you should be able to do afterwards

You should be able to:

- relate `Deployment`, `ReplicaSet` and `Pod`;
- explain how a `Service` selects Pods using labels;
- use `get`, `describe`, `logs` and `exec` to obtain evidence;
- access a Service temporarily with `port-forward`;
- observe Pod replacement;
- scale a Deployment;
- distinguish the current cluster state from the desired state stored in YAML.

You are **not** expected to memorize every `kubectl` command.

---

# 0. Check your environment

Complete the course login procedure and run the shared preflight:

```bash
./scripts/preflight.sh
```

Continue only when the essential Kubernetes checks are `PASS`.

Inspect your current context and namespace:

```bash
kubectl config current-context
kubectl config view --minify --output 'jsonpath={..namespace}'; echo
```

List existing Pods:

```bash
kubectl get pods
```

### Checkpoint

Why is it useful that your namespace is already selected in the current context?

---

# 1. Inspect before applying

Open:

```text
manifests/01-inventory-deployment.yaml
```

Locate only these elements:

- `kind`;
- `metadata.name`;
- `spec.replicas`;
- `spec.selector`;
- labels in the Pod template;
- container image;
- container port.

Before applying it, answer:

1. How many Inventory Pods should Kubernetes create?
2. Which label identifies an Inventory Pod?
3. What relationship do you see between `selector.matchLabels` and the Pod labels?

Do not try to memorize the whole manifest.

---

# 2. Deploy Inventory

Apply the Deployment:

```bash
kubectl apply -f labs/p00-kubernetes-survival-kit/manifests/01-inventory-deployment.yaml
```

Observe the resources:

```bash
kubectl get deployments
kubectl get replicasets
kubectl get pods
```

### Checkpoint

Complete the model:

```text
Deployment
    ↓
??????????
    ↓
Pod
```

Which object is missing, and what is its role?

---

# 3. Give Inventory a stable network identity

Apply the Service:

```bash
kubectl apply -f labs/p00-kubernetes-survival-kit/manifests/02-inventory-service.yaml
```

Inspect:

```bash
kubectl get services
kubectl get pods --show-labels
kubectl get service inventory -o yaml
kubectl get endpointslice -l kubernetes.io/service-name=inventory
```

### Investigate

How does `Service/inventory` know which Pod should receive traffic?

Use evidence from:

- the Service selector;
- Pod labels;
- the EndpointSlice.

Do not answer only from memory: point to the evidence.

---

# 4. Deploy Orders

Apply Orders:

```bash
kubectl apply -f labs/p00-kubernetes-survival-kit/manifests/03-orders-deployment.yaml
kubectl apply -f labs/p00-kubernetes-survival-kit/manifests/04-orders-service.yaml
```

Inspect the system:

```bash
kubectl get deployments,replicasets,pods,services
```

At this point you should have one Orders Pod and one Inventory Pod.

---

# 5. Use the application

Open one terminal and run:

```bash
kubectl port-forward service/orders 8080:8080
```

Keep that terminal open.

In a second terminal:

```bash
curl 'http://localhost:8080/api/orders/preview?sku=SKU-001&quantity=2' | jq
```

A successful response should contain fields similar to:

```json
{
  "sku": "SKU-001",
  "quantity": 2,
  "canBeFulfilled": true,
  "inventoryAvailable": 42,
  "servedBy": "orders-...",
  "inventoryServedBy": "inventory-...",
  "serviceVersion": "0.1.1"
}
```

The `servedBy` fields are a **training aid** so that replica behaviour is observable. They are not a recommendation for a public production API.

### Checkpoint

Which service did your browser/terminal contact directly? Which service was contacted indirectly?

---

# 6. Obtain evidence from Kubernetes

Capture the Orders Pod name:

```bash
ORDERS_POD=$(kubectl get pod \
  -l app.kubernetes.io/name=orders \
  -o jsonpath='{.items[0].metadata.name}')

echo "$ORDERS_POD"
```

Read application logs:

```bash
kubectl logs "$ORDERS_POD"
```

Look for the Inventory call.

Now describe the Pod:

```bash
kubectl describe pod "$ORDERS_POD"
```

Locate:

- image;
- state;
- readiness state;
- Pod IP;
- environment variables;
- events.

### Checkpoint

What question would you answer with `logs`? What different question would you answer with `describe`?

---

# 7. Verify service discovery from inside Orders

From the Orders Pod, call Inventory using the **Service name**, not a Pod IP:

```bash
kubectl exec "$ORDERS_POD" -- \
  curl -s http://inventory:8080/api/inventory/SKU-001 | jq
```

### Checkpoint

Why can Orders use:

```text
http://inventory:8080
```

instead of a Pod IP?

What would happen to a design that stored a Pod IP directly?

---

# 8. Destroy a Pod deliberately

Before executing the command, **predict the result**.

```bash
kubectl delete pod "$ORDERS_POD"
```

Watch:

```bash
kubectl get pods -w
```

Stop the watch with `Ctrl+C` after the replacement Pod becomes ready.

Then:

```bash
kubectl get pods -l app.kubernetes.io/name=orders -o wide
```

### Explain what happened

1. Which controller caused a replacement Pod to exist?
2. Did the replacement keep the old Pod name?
3. Should Orders' clients depend on the Pod name or Pod IP?
4. Did the Kubernetes Service need to be recreated?

---

# 9. Scale Inventory

Scale Inventory from one replica to three:

```bash
kubectl scale deployment inventory --replicas=3
```

Observe:

```bash
kubectl get pods -l app.kubernetes.io/name=inventory
kubectl get endpointslice -l kubernetes.io/service-name=inventory -o wide
```

Wait until all three Pods are ready.

Execute several calls through Orders:

```bash
for i in {1..10}; do
  curl -s 'http://localhost:8080/api/orders/preview?sku=SKU-001&quantity=2' \
    | jq -r '.inventoryServedBy'
done
```

You may observe different Inventory instances serving requests. Do not expect a perfectly even 10-request distribution.

### Checkpoint

The Service object is still one object. What changed behind it?

---

# 10. Desired state surprise

Open again:

```text
manifests/01-inventory-deployment.yaml
```

Check `spec.replicas`.

Your cluster currently has three Inventory replicas, but the file says something different.

**Predict what will happen before running the next command.**

```bash
kubectl apply -f labs/p00-kubernetes-survival-kit/manifests/01-inventory-deployment.yaml
```

Verify:

```bash
kubectl get deployment inventory
kubectl get pods -l app.kubernetes.io/name=inventory
```

### Checkpoint

What is the difference between:

```bash
kubectl scale deployment inventory --replicas=3
```

and changing the declarative configuration stored in Git?

---

# 11. Verify the lab

Run:

```bash
./labs/p00-kubernetes-survival-kit/scripts/verify.sh
```

A successful run should end with zero failed checks.

The objective is not merely to get `PASS`. Be ready to explain **why** every check passes. Record four short notes — *predicted, changed, observed, concluded* — and one piece of evidence from Kubernetes or HTTP.

---

# What changed?

At the beginning you had manifests but no application workload running in your namespace.

You now have observed:

```text
Deployment → ReplicaSet → Pod(s)

Service → selector → EndpointSlice → Pod IPs

Orders → Kubernetes DNS → Inventory

Pod deleted → controller restores desired replica count

1 Inventory replica → 3 replicas → declarative state reapplied
```

---

# Debrief preparation

Be ready to discuss:

1. What recreates a Pod when one controlled by a Deployment is deleted?
2. What evidence proves how a Service finds its destinations?
3. Why should Pods be treated as replaceable instances?
4. Does `Running` prove that an application is healthy?
5. Does scaling from one to three Pods prove that the whole system has three times the capacity?
6. What important production concerns have we deliberately not solved yet?

Those unanswered concerns become the starting point for the next practices.
