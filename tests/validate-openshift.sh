#!/bin/sh
set -eu

namespace=${1:?usage: validate-openshift.sh NAMESPACE QUERY_IMAGE COLLECTOR_IMAGE}
query_image=${2:?usage: validate-openshift.sh NAMESPACE QUERY_IMAGE COLLECTOR_IMAGE}
collector_image=${3:?usage: validate-openshift.sh NAMESPACE QUERY_IMAGE COLLECTOR_IMAGE}
instance=${JAEGER_INSTANCE:-wellcare-jaeger}

command -v oc >/dev/null
oc -n "$namespace" get jaeger "$instance" -o name >/dev/null

for component in query collector; do
  deployment="${instance}-${component}"
  oc -n "$namespace" rollout status "deployment/$deployment" --timeout=5m
  images=$(oc -n "$namespace" get deployment "$deployment" -o jsonpath='{.spec.template.spec.containers[*].image}')
  case "$component:$images" in
    query:*"$query_image"*) ;;
    collector:*"$collector_image"*) ;;
    *) echo "$deployment does not use the expected immutable image: $images" >&2; exit 1 ;;
  esac
  logs=$(oc -n "$namespace" logs "deployment/$deployment" --all-containers=true --since=15m 2>&1 || true)
  if printf '%s' "$logs" | grep -F 'unknown flag' >/dev/null; then
    printf '%s\n' "$logs" >&2
    exit 1
  fi
done

oc -n "$namespace" get service "${instance}-query" "${instance}-collector"
oc -n "$namespace" get route -l "app.kubernetes.io/instance=$instance" || true
echo "Read-only rollout, image, service, route, and unknown-flag checks passed."
echo "Synthetic trace persistence/retrieval and TLS endpoint tests must still be run in the isolated test namespace."
