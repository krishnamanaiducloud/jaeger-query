# Jaeger v1 query service hardened compatibility build

This repository builds Jaeger Query **v1.65.0** for deployments managed by the legacy
Jaeger Operator and `jaegertracing.io/v1` custom resources. It intentionally does not
contain a Jaeger v2 binary.

The immutable image tag is `mohankrishna999/jaeger-query:1.65.0.1-patched`. It preserves
the official v1 runtime contract:

- entrypoint `/go/bin/query-linux`;
- Jaeger v1 flags such as `--es.server-urls` and `--query.http.tls.cert`;
- ports 16685 (gRPC), 16686 (HTTP/UI), and 16687 (admin/health/metrics);
- non-root execution with primary GID 0 for OpenShift arbitrary-UID compatibility;
- embedded Jaeger UI and the system CA trust bundle.

The source is pinned to Jaeger v1.65.0 commit
`b3be0117dc69484a47addb38aa18f599315622da`. Vulnerable Go dependencies are upgraded in
the build stage, component tests run before compilation, and the final static image does
not contain a shell or package manager.

## Verification

```sh
make compatibility
make scan
make sbom
```

`tests/verify-cli-contract.sh` fails if the binary changes to v2, loses an Operator-used
flag, cannot load TLS certificates, cannot start with an OpenShift-style random UID and a
read-only root filesystem, or fails to serve the query API.

Jaeger v1 reached end of life on December 31, 2025. This build repairs the existing v1
deployment contract; it is not a substitute for a separately approved Jaeger v2 migration.
