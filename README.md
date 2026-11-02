# Jaeger v2 query service hardened source build

Jaeger 2.22.0 rebuilt from verified upstream source with its UI assets and placed in a shell-less Chainguard static runtime. Published as `mohankrishna999/jaeger-query:2.22.0-patched` for amd64 and arm64.

The default configuration uses Elasticsearch at `ES_SERVER_URL` (default `http://elasticsearch:9200`). Mount a complete Jaeger v2 configuration over `/cmd/jaeger/config.yaml` for another storage backend.

The image runs as UID 10001 with GID 0 and the included manifests satisfy Kubernetes restricted Pod Security and OpenShift restricted SCC requirements.

