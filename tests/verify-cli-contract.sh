#!/bin/sh
set -eu

image=${1:?usage: verify-cli-contract.sh IMAGE}
name="jaeger-query-contract-$$"
tmpdir=$(mktemp -d)

cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  rm -rf "$tmpdir"
}
trap cleanup EXIT INT TERM

config=$(docker image inspect "$image" --format '{{json .Config}}')
printf '%s' "$config" | grep -F '"Entrypoint":["/go/bin/query-linux"]' >/dev/null
printf '%s' "$config" | grep -F '"User":"10001:0"' >/dev/null

version=$(docker run --rm "$image" version 2>&1)
printf '%s' "$version" | grep -F 'git-version=v1.65.0' >/dev/null
if printf '%s' "$version" | grep -F 'git-version=v2.' >/dev/null; then
  echo "unexpected Jaeger v2 binary" >&2
  exit 1
fi

help=$(docker run --rm -e SPAN_STORAGE_TYPE=elasticsearch "$image" --help 2>&1)
for flag in \
  --es.server-urls \
  --es.tls.enabled \
  --es.tls.ca \
  --es.tls.cert \
  --es.tls.key \
  --es.timeout \
  --es.num-shards \
  --es.num-replicas \
  --query.base-path \
  --query.ui-config \
  --query.http.tls.enabled \
  --query.http.tls.cert \
  --query.http.tls.key \
  --query.grpc.tls.enabled \
  --query.grpc.tls.cert \
  --query.grpc.tls.key; do
  printf '%s' "$help" | grep -F -- "$flag" >/dev/null || {
    echo "missing required query flag: $flag" >&2
    exit 1
  }
done

openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj /CN=localhost -keyout "$tmpdir/tls.key" -out "$tmpdir/tls.crt" >/dev/null 2>&1
chmod 0755 "$tmpdir"
chmod 0444 "$tmpdir/tls.key" "$tmpdir/tls.crt"

docker run -d --name "$name" \
  --user 1000710000:0 \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,mode=1777 \
  -v "$tmpdir:/tls:ro" \
  -p 127.0.0.1:0:16686 \
  -p 127.0.0.1:0:16687 \
  -e SPAN_STORAGE_TYPE=memory \
  "$image" \
  --query.http-server.host-port=0.0.0.0:16686 \
  --admin.http.host-port=0.0.0.0:16687 \
  --query.http.tls.enabled=true \
  --query.http.tls.cert=/tls/tls.crt \
  --query.http.tls.key=/tls/tls.key >/dev/null

query_address=$(docker port "$name" 16686/tcp)
admin_address=$(docker port "$name" 16687/tcp)
attempt=0
until curl --fail --silent --show-error "http://${admin_address}/" >/dev/null \
  && curl --fail --insecure --silent --show-error "https://${query_address}/api/services" >/dev/null; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 30 ]; then
    docker logs "$name" >&2
    exit 1
  fi
  sleep 1
done
