# Jaeger v1 image repair report

Status: immutable multi-architecture images built, tested, and published; not deployed.

This report covers the paired `jaeger-query` and `jaeger-collector` repairs. It is
copied into both repositories so that either release remains independently auditable.

## Root cause

The failed `2.23.0.1-patched` images were not patched versions of the working Jaeger
v1 component images. They built the Jaeger v2 unified binary, installed it at
`/cmd/jaeger/jaeger`, and changed the entrypoint to that binary plus a v2 configuration
file. The legacy Jaeger Operator still generated the v1 component CLI contract. The v2
binary therefore rejected `--es.server-urls`, `--collector.grpc.tls.cert`, and other v1
flags before either component could start.

Changing Helm flags would not be a safe repair: `jaegertracing.io/v1` and the archived
Jaeger Operator deploy the v1 architecture, while v2 uses a different application and
configuration model. The smallest compatible fix is to build the original component
binaries from the pinned Jaeger v1.65.0 source and update only their dependencies and
runtime image.

## Inspected image evidence

All rows below were inspected as Linux/amd64 images on 2026-11-11. The fixed image rows
show the platform manifest IDs. They are members of the published manifest lists recorded
below.

| Component/image | Manifest ID or digest | Entrypoint | Version | Binary SHA-256 |
|---|---|---|---|---|
| official query `jaegertracing/jaeger-query:1.65.0` | `sha256:5bac2830a388641072634803e3942f0d00f9d5e5c9832f6938ef39368a325464` | `/go/bin/query-linux` | v1.65.0 | `03908851282a3e216f810edf6f26c9226e40c32c3c1daa021e0d515536eb36a1` |
| broken query `2.23.0.1-patched` | `sha256:55d992a08da81e99992ddca8df6a207b942e30090ea1447ed83f` | `/cmd/jaeger/jaeger` | v2.23.0 | `6bfb104802b7649ad83dfe7cbaa57a6f55088d926bc042709460d9115ef97fd5` |
| fixed query `1.65.0.1-patched` | `sha256:5cebc1f74b7cf1e6cbd095f30c3d6569aa08196bb02bc4fba10e78fab72aca19` | `/go/bin/query-linux` | v1.65.0 | `1434aed2c3ae1ad2e8eddd033b47e106947ad9b2b363e16d30162b9045f3769e` |
| official collector `jaegertracing/jaeger-collector:1.65.0` | `sha256:8a1611f0e256d5b99f018a82f80b15003c0c5c5fd36e173896a995556a72730e` | `/go/bin/collector-linux` | v1.65.0 | `517b4e6e58c450f6a9cc15254cd41f05734aa5cac68fdb92a01676c493f96965` |
| broken collector `2.23.0.1-patched` | `sha256:c9605d14df4eb41a2bb0aaf0b779d9ec5d83886142d69ebd7a6a45f56788e53e` | `/cmd/jaeger/jaeger` | v2.23.0 | `6bfb104802b7649ad83dfe7cbaa57a6f55088d926bc042709460d9115ef97fd5` |
| fixed collector `1.65.0.1-patched` | `sha256:6b4b639b21448075b17e81d3b46e57f2d810b570a5a37b22664a9e710b0c2137` | `/go/bin/collector-linux` | v1.65.0 | `3adabb4483ccbf3da17bcef6db0f9ac001bac5694b87bea844502b85eaba0495` |

Published immutable references:

- `docker.io/mohankrishna999/jaeger-query@sha256:60f6b419590daae07ed5f8bd8aa64cb0802a9e908c4d381bc6f9cb2dad5020cb`
  (`linux/amd64` and `linux/arm64`)
- `docker.io/mohankrishna999/jaeger-collector@sha256:d31e986d69b98023865974bb65f8dd65bd03ed01add795a5ef50503edf9b380d`
  (`linux/amd64` and `linux/arm64`)

The identical broken query/collector checksum proves both images contained the same
unified v2 executable rather than their respective v1 components. The fixed binaries are
statically linked and stripped. They deliberately differ from the official checksums
because dependency security fixes and reproducible linker settings changed the build.

The fixed query exposes 16685, 16686, and 16687. The fixed collector exposes 4317, 4318,
9411, 14250, 14268, and 14269. Both use UID `10001`, primary GID `0`, a shell-free
digest-pinned Chainguard static runtime, and
`SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt`. Minimus static and Go images were
evaluated first, but the configured registry returned HTTP 403 and could not be used in a
reproducible unauthenticated build.

## Implemented compatibility and security controls

- Source is pinned to Jaeger v1.65.0 commit
  `b3be0117dc69484a47addb38aa18f599315622da`.
- Official component paths and entrypoints are restored.
- Base images are pinned by digest and the final runtime contains no shell or package
  manager.
- Go dependencies with fixes are explicitly pinned and verified by the build script.
- Component, Elasticsearch storage, and TLS package tests run before compilation.
- The query patch removes deprecated `otelhttp.WithRouteTag`; current OpenTelemetry adds
  the span route automatically. The only other query patch updates a Go 1.27 test error
  message. The collector patch updates a test-only IPv6 URL construction for Go 1.27.
- Runtime contract tests check all known Operator-generated storage and TLS flags, v1
  version identity, arbitrary UID execution, read-only root filesystem behavior, TLS
  loading, health endpoints, the query API, and two concurrent collector replicas.
- Kustomize examples use the repaired v1 tags and restricted container security settings.
- CycloneDX SBOMs are stored under `sbom/`.

## Executed test evidence

Executed on 2026-11-11:

| Gate | Query | Collector |
|---|---|---|
| Docker build, Linux/amd64 | pass | pass |
| Upstream component/ES/TLS tests | pass | pass |
| CLI and runtime contract test | pass | pass (two replicas) |
| Trivy 0.76.2, all severities, OS + libraries, fixed and unfixed | 0 findings | 0 findings |
| Grype 0.121.3, fail at negligible | 0 findings | 0 findings |
| CycloneDX SBOM (Syft 1.57.1) | generated | generated |
| Hadolint 2.14.0 | pass | pass |
| Kustomize + kubeconform 0.7.0 | 2 valid, 0 invalid | 2 valid, 0 invalid |

Trivy used a database updated at `2026-11-11T19:04:54Z`. Grype used the current schema 6
database downloaded on the test date. No scanner exclusions, ignore files, or severity
suppression were used. These results apply only to the tested local manifests and scanner
databases. After publication, both tools also scanned the immutable registry manifest-list
digests directly and reported zero findings. Registry-side Wiz scanning remains an
independent required check because Wiz access is unavailable here.

## Helm and OpenShift integration

The referenced `app-monitoring/jaeger/templates/instance.yaml`, Helm release, cluster,
internal Artifactory, original production image digests, and Elasticsearch endpoint were
not available in this workspace. Consequently Helm lint/rendering, Operator
reconciliation, real Elasticsearch persistence, trace ingestion/retrieval, routes, OAuth,
and restart recovery were not executed and must not be represented as passed.

When the chart is supplied, make the two images configurable and preserve every existing
field in the Jaeger CR:

```yaml
# values.yaml
jaeger:
  images:
    query: INTERNAL_REGISTRY/jaeger-query@sha256:APPROVED_QUERY_DIGEST
    collector: INTERNAL_REGISTRY/jaeger-collector@sha256:APPROVED_COLLECTOR_DIGEST
```

```yaml
# inside spec of templates/instance.yaml
query:
  image: {{ required "jaeger.images.query is required" .Values.jaeger.images.query | quote }}
collector:
  image: {{ required "jaeger.images.collector is required" .Values.jaeger.images.collector | quote }}
```

Do not replace the existing `query` or `collector` maps; merge the `image` keys into them
so TLS mounts, options, resources, replicas, labels, and OpenShift settings remain intact.
Render and validate the actual chart before rollout:

```sh
helm lint app-monitoring/jaeger -f APPROVED_VALUES.yaml
helm template RELEASE app-monitoring/jaeger -n NAMESPACE -f APPROVED_VALUES.yaml > rendered.yaml
kubeconform -strict -summary -ignore-missing-schemas rendered.yaml
```

Use `scripts/capture-openshift-state.sh` before any change and
`tests/validate-openshift.sh` after the Operator reconciles.

## Rollback

Rollback is documented but unverified because no cluster was available.

1. Record the exact current Helm values, rendered manifest, Jaeger CR, deployments,
   services, routes, secret names, image IDs, and Elasticsearch settings with the capture
   script. Do not export secret contents.
2. Commit the candidate digest changes through the existing GitOps path. Do not overwrite
   a known-good tag.
3. If validation fails, revert only the two image values to the captured known-good
   digests and run the normal Helm/GitOps reconciliation.
4. Wait for `wellcare-jaeger-query` and `wellcare-jaeger-collector` rollouts, then rerun
   the validation script.
5. Do not delete or recreate the Jaeger CR, Elasticsearch indices, PVCs, TLS secrets,
   Services, or Routes.

An emergency direct cluster patch is intentionally not supplied because production
mutation was not authorized. Use the chart/GitOps rollback unless an incident commander
explicitly authorizes a direct patch.

## Remaining risks and release blockers

- Jaeger v1 reached end of life on 2025-12-31. Dependency patching reduces known findings
  but cannot restore upstream support. A separately approved v2 migration remains
  necessary.
- The legacy Jaeger Operator is also deprecated/archived.
- The actual chart and cluster tests listed above are mandatory release blockers.
- Elasticsearch version, credentials, CA chain, index mappings, and TLS behavior have not
  been tested against the real service.
- Only Linux/amd64 was locally loaded and executed. The push target is multi-architecture,
  but Linux/arm64 must pass CI on native or emulated runners before publication.
- Image signing is blocked until the target registry and signing identity are provided.
- Trivy's generic configuration policy reports the intentionally unset namespace,
  arbitrary OpenShift UID/GID, pre-promotion Docker Hub image, and absent Dockerfile
  `HEALTHCHECK`. The real namespace and internal digest are chart/promotion inputs;
  setting a fixed UID/GID would break OpenShift, and Kubernetes liveness/readiness probes
  replace a Dockerfile health check in the shell-free runtime. These notices remain
  visible in CI rather than being suppressed.
- Future vulnerability databases or Wiz policies can produce new findings; no image can
  be guaranteed permanently vulnerability-free.

## File change rationale

- `Dockerfile`: restores pinned v1 component builds and hardened runtime behavior.
- `build/patch-modules.sh`: applies and verifies fixed Go module versions.
- `build/*-compat.patch`: narrow source/test compatibility for current Go/OpenTelemetry.
- `config.yaml` (removed): it was v2-only configuration that caused the architecture swap.
- `tests/verify-cli-contract.sh`: prevents another v1-to-v2 binary substitution.
- `tests/validate-openshift.sh`: read-only post-reconciliation checks for the real cluster.
- `scripts/capture-openshift-state.sh`: captures rollback evidence without secret values.
- `k8s/*`: corrected component tags, ports, health probes, storage flags, and restricted
  security context.
- `Makefile`: reproducible build, test, scan, SBOM, and explicitly separate push target.
- `.github/workflows/container-security.yml`: blocks changes on compatibility/security
  gates and publishes test evidence, not container images.
- `sbom/*`: component inventory for review and registry scanning.
- `README.md`: documents the supported v1 contract and EOL boundary.
