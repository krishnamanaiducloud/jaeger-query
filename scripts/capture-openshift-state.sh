#!/bin/sh
set -eu

namespace=${1:?usage: capture-openshift-state.sh NAMESPACE [HELM_RELEASE] [OUTPUT_DIR]}
release=${2:-}
output=${3:-jaeger-state-$(date -u +%Y%m%dT%H%M%SZ)}
instance=${JAEGER_INSTANCE:-wellcare-jaeger}

command -v oc >/dev/null
mkdir -p "$output"

oc -n "$namespace" get jaeger "$instance" -o yaml --show-managed-fields=false >"$output/jaeger-cr.yaml"
oc -n "$namespace" get deployment,statefulset,pod,service,route -l "app.kubernetes.io/instance=$instance" \
  -o yaml --show-managed-fields=false >"$output/workloads-services-routes.yaml" || true
oc -n "$namespace" get deployment "${instance}-query" "${instance}-collector" \
  -o yaml --show-managed-fields=false >"$output/component-deployments.yaml"
oc -n "$namespace" get secret -o name >"$output/secret-names.txt"
oc -n "$namespace" get pvc -o yaml --show-managed-fields=false >"$output/pvcs.yaml"
oc -n "$namespace" get events --sort-by=.lastTimestamp >"$output/events.txt"

if [ -n "$release" ]; then
  command -v helm >/dev/null
  helm -n "$namespace" get values "$release" --all >"$output/helm-values.yaml"
  helm -n "$namespace" get manifest "$release" >"$output/helm-manifest.yaml"
fi

echo "Captured rollback metadata in $output (secret names only; no secret values)."
