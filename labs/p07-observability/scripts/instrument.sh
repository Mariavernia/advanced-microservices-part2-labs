#!/usr/bin/env bash
set -euo pipefail
# P07 pilot: instrument existing workloads, preserving P05 JWT and P06 mesh.
# No cluster administration or changes to base images. Run from student Codespace.
# Usage: bash labs/p07-observability/scripts/instrument.sh
#        CONFIRM_P07_INSTRUMENT=YES bash labs/p07-observability/scripts/instrument.sh

NS="$(kubectl config view --minify -o jsonpath='{..namespace}')"
[[ "$NS" =~ ^student(0[1-9]|1[0-9]|2[0-3])$ ]] || { echo "[FAIL] Student namespace required"; exit 2; }
[[ "$(kubectl config current-context)" == aks-advms26-course ]] || { echo "[FAIL] Wrong cluster"; exit 2; }
[[ "$(az account show --query user.name -o tsv)" == "$NS@training.cloudsecurityinpractice.com" ]] || { echo "[FAIL] Wrong student identity"; exit 2; }
kubectl get deploy p07-jaeger -o json | jq -e '.status.readyReplicas==1' >/dev/null
[[ "$(kubectl get peerauthentication -o json | jq '.items|length')" == 0 ]] || { echo "[FAIL] Remove the P06 temporary STRICT policy first"; exit 2; }

# Official linux/amd64 image, pinned manifest digest (AKS x86 nodes).
AGENT="ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:2.30.0@sha256:f5133aceb480d0779b8ce288a52ddbc80414ba9774818de111f2351f02f3eb94"
APPS=(inventory orders api-gateway)
declare -A OLD_REV
declare -a CHANGED=()

patch_for() {
  jq -nc --arg app "$1" --arg image "$AGENT" '
  {spec:{template:{spec:{
    securityContext:{fsGroup:10001},
    volumes:[{name:"p07-otel-agent",emptyDir:{sizeLimit:"96Mi"}}],
    initContainers:[{
      name:"p07-otel-agent",image:$image,imagePullPolicy:"IfNotPresent",
      command:["cp","/javaagent.jar","/otel/javaagent.jar"],
      securityContext:{runAsNonRoot:true,runAsUser:10001,runAsGroup:10001,allowPrivilegeEscalation:false,capabilities:{drop:["ALL"]}},
      resources:{requests:{cpu:"50m",memory:"64Mi"},limits:{cpu:"200m",memory:"128Mi"}},
      volumeMounts:[{name:"p07-otel-agent",mountPath:"/otel"}]
    }],
    containers:[{
      name:$app,
      resources:{requests:{memory:"256Mi"},limits:{memory:"768Mi"}},
      volumeMounts:[{name:"p07-otel-agent",mountPath:"/otel",readOnly:true}],
      env:[
        {name:"JAVA_TOOL_OPTIONS",value:"-javaagent:/otel/javaagent.jar"},
        {name:"OTEL_SERVICE_NAME",value:$app},
        {name:"OTEL_EXPORTER_OTLP_TRACES_ENDPOINT",value:"http://p07-jaeger:4318/v1/traces"},
        {name:"OTEL_EXPORTER_OTLP_PROTOCOL",value:"http/protobuf"},
        {name:"OTEL_TRACES_EXPORTER",value:"otlp"},
        {name:"OTEL_METRICS_EXPORTER",value:"none"},
        {name:"OTEL_LOGS_EXPORTER",value:"none"},
        {name:"OTEL_TRACES_SAMPLER",value:"parentbased_always_on"},
        {name:"OTEL_PROPAGATORS",value:"tracecontext,baggage"},
        {name:"OTEL_BSP_SCHEDULE_DELAY",value:"1000"}
      ]
    }]
  }}}}'
}

for APP in "${APPS[@]}"; do
  obj="$(kubectl get deploy "$APP" -o json)"
  jq -e --arg app "$APP" '
    .spec.replicas==1 and .status.readyReplicas==1 and
    .status.updatedReplicas==1 and .status.observedGeneration==.metadata.generation
    and ((.spec.template.spec.securityContext.fsGroup // 10001)==10001)
    and ([.spec.template.spec.containers[]|select(.name==$app)]|length)==1
    and ([.spec.template.spec.containers[]|select(.name==$app)|.env[]?|
      select(.name=="JAVA_TOOL_OPTIONS" or (.name|startswith("OTEL_")))]|length)==0
    and ([.spec.template.spec.initContainers[]?|select(.name=="p07-otel-agent")]|length)==0
    and ([.spec.template.spec.volumes[]?|select(.name=="p07-otel-agent")]|length)==0
  ' <<<"$obj" >/dev/null || { echo "[FAIL] $APP not stable or already instrumented; no changes"; exit 2; }
  OLD_REV[$APP]="$(jq -er '.metadata.annotations["deployment.kubernetes.io/revision"]' <<<"$obj")"
  kubectl patch deployment "$APP" --type=strategic --dry-run=server -p "$(patch_for "$APP")" >/dev/null
  echo "[PASS] $APP patch accepted; original revision ${OLD_REV[$APP]}"
done

echo "[INFO] Preserves app image, CPU, P05 configuration and P06 Pod labels."
echo "[INFO] Adds agent init container, emptyDir and memory request/limit 256Mi/768Mi."
echo "[INFO] Trace sampling 100% for pilot only; metrics/log exporters disabled."
[[ "${CONFIRM_P07_INSTRUMENT:-}" == YES ]] || { echo "[INFO] No changes; set CONFIRM_P07_INSTRUMENT=YES"; exit 0; }

rollback() {
  local rc=$?
  trap - EXIT
  if (( rc != 0 )); then
    echo "[WARN] Instrumentation failed; restoring modified Deployments only."
    for (( i=${#CHANGED[@]}-1; i>=0; i-- )); do
      APP="${CHANGED[$i]}"
      kubectl rollout undo deployment/"$APP" --to-revision="${OLD_REV[$APP]}" || true
      kubectl rollout status deployment/"$APP" --timeout=180s || true
    done
  fi
  exit "$rc"
}
trap rollback EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for APP in "${APPS[@]}"; do
  echo "===== INSTRUMENT $APP ====="
  CHANGED+=("$APP")
  kubectl patch deployment "$APP" --type=strategic -p "$(patch_for "$APP")"
  kubectl rollout status deployment/"$APP" --timeout=240s
  # Some baseline workloads do not have HTTP readiness probes, so verify app.
  ok=false
  for attempt in $(seq 1 20); do
    if kubectl exec deployment/"$APP" -c "$APP" -- curl -fsS --max-time 4 http://127.0.0.1:8080/actuator/health >/dev/null 2>&1; then
      ok=true; break
    fi
    sleep 3
  done
  [[ "$ok" == true ]] || { echo "[FAIL] $APP health not reachable"; exit 1; }
  kubectl get pods -l "app.kubernetes.io/name=$APP" -o json |
    jq -e '[.items[]|select(.metadata.deletionTimestamp==null)|select(any(.status.initContainerStatuses[]?; .name=="p07-otel-agent" and .state.terminated.exitCode==0))]|length==1' >/dev/null
  echo "[PASS] $APP agent copied and application healthy."
done
kubectl exec deployment/orders -c orders -- curl -fsS --max-time 20 'http://127.0.0.1:8080/api/orders/preview?sku=SKU-001&quantity=2' | jq -e '.canBeFulfilled==true'
kubectl get pods -l 'app.kubernetes.io/name in (inventory,orders,api-gateway,p07-jaeger)'
echo "[PASS] P07 applications instrumented; next verify real traces in Jaeger."
echo "[INFO] Preserve original revision numbers above for cleanup; no authentication configuration changed."
