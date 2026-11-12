#!/bin/sh
# Raise vulnerable modules in Jaeger v1.65.0 without changing its CLI contract.
# Run inside the upstream source tree.
set -eu

# Retry transient module proxy and checksum database failures.
retry() {
  attempt=1
  until "$@"; do
    if [ "$attempt" -ge 4 ]; then
      return 1
    fi
    echo "Command failed (attempt $attempt), retrying: $*" >&2
    sleep $((attempt * 5))
    attempt=$((attempt + 1))
  done
}

PINS="github.com/apache/thrift@v0.25.0 github.com/go-viper/mapstructure/v2@v2.5.0 github.com/klauspost/compress@v1.20.3 go.opentelemetry.io/otel/exporters/otlp/otlptrace@v1.47.0 go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc@v1.47.0 go.opentelemetry.io/otel/sdk@v1.47.0 golang.org/x/crypto@v0.58.1-0.20261009181718-2f1f834330b2 golang.org/x/net@v0.62.0 golang.org/x/oauth2@v0.37.0 golang.org/x/sys@v0.49.0 golang.org/x/text@v0.43.0 google.golang.org/grpc@v1.84.0 google.golang.org/protobuf@v1.36.12"

# shellcheck disable=SC2086
retry go get $PINS
# Newer OpenTelemetry releases removed a test-only internal package. Keep the usable module
# graph and let the mandatory component tests below determine runtime compatibility.
retry go mod tidy -e

# Fail the build if any pin was not applied.
for pin in $PINS; do
  module=${pin%@*}
  want=${pin#*@}
  have=$(go list -m -f '{{.Version}}' "$module")
  if [ "$have" != "$want" ]; then
    echo "module $module is $have, want $want" >&2
    exit 1
  fi
done
