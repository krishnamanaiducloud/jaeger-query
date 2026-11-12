# syntax=docker/dockerfile:1.7
ARG BUILD_IMAGE=cgr.dev/chainguard/wolfi-base:latest@sha256:8509ee4351a2e501b7f98201f2e2642396e82020c61a589cacdcfe74b9de46c1
ARG RUNTIME_IMAGE=cgr.dev/chainguard/static:latest@sha256:fc42af33e643f20d08baf03cddcc1c02ba57052dfb02edb0d79f3fc47bcea8d9

FROM --platform=$BUILDPLATFORM ${BUILD_IMAGE} AS source
ARG JAEGER_VERSION=1.65.0
ARG JAEGER_COMMIT=b3be0117dc69484a47addb38aa18f599315622da

COPY build/apk-install.sh /usr/local/bin/apk-install
RUN sh /usr/local/bin/apk-install bash build-base curl git go gzip make nodejs-24 npm
ENV CGO_ENABLED=0 GOTOOLCHAIN=local
WORKDIR /src
RUN git -c advice.detachedHead=false clone --quiet --depth 1 --recurse-submodules --shallow-submodules \
      --branch "v${JAEGER_VERSION}" https://github.com/jaegertracing/jaeger.git . \
    && test "$(git rev-parse HEAD)" = "${JAEGER_COMMIT}"

FROM source AS ui
RUN make build-ui

FROM ui AS patched
COPY build/patch-modules.sh /usr/local/bin/patch-modules.sh
COPY build/otelhttp-compat.patch /tmp/otelhttp-compat.patch
RUN --mount=type=cache,id=jaeger-v1-go-mod,target=/root/go/pkg/mod,sharing=locked \
    git apply --check /tmp/otelhttp-compat.patch \
    && git apply /tmp/otelhttp-compat.patch \
    && sh /usr/local/bin/patch-modules.sh

FROM patched AS tested
RUN --mount=type=cache,id=jaeger-v1-go-mod,target=/root/go/pkg/mod,sharing=locked \
    --mount=type=cache,id=jaeger-v1-go-build,target=/root/.cache/go-build,sharing=locked \
    go test -trimpath -p=2 ./cmd/query/... ./plugin/storage/es/... ./pkg/config/tlscfg/...

FROM tested AS build
ARG TARGETOS
ARG TARGETARCH
ARG JAEGER_VERSION=1.65.0
ARG JAEGER_COMMIT=b3be0117dc69484a47addb38aa18f599315622da
RUN --mount=type=cache,id=jaeger-v1-go-mod,target=/root/go/pkg/mod,sharing=locked \
    --mount=type=cache,id=jaeger-v1-go-build,target=/root/.cache/go-build,sharing=locked \
    v=github.com/jaegertracing/jaeger/pkg/version \
    && date="$(TZ=UTC0 git show --quiet --date='format-local:%Y-%m-%dT%H:%M:%SZ' --format='%cd' "${JAEGER_COMMIT}")" \
    && GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" go build -trimpath -buildvcs=false \
      -ldflags "-s -w -buildid= -X ${v}.commitSHA=${JAEGER_COMMIT} -X ${v}.latestVersion=v${JAEGER_VERSION} -X ${v}.date=${date}" \
      -o /out/query-linux ./cmd/query \
    && chmod 0555 /out/query-linux \
    && go version -m /out/query-linux > /tmp/query-buildinfo \
    && grep -F "GOARCH=${TARGETARCH}" /tmp/query-buildinfo

FROM ${RUNTIME_IMAGE}
ARG JAEGER_VERSION=1.65.0
ARG JAEGER_COMMIT=b3be0117dc69484a47addb38aa18f599315622da
ARG IMAGE_VERSION=1.65.0.1-patched
LABEL org.opencontainers.image.title="jaeger-query" \
      org.opencontainers.image.description="OpenShift-compatible Jaeger v1 query service" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${JAEGER_COMMIT}" \
      org.opencontainers.image.source="https://github.com/jaegertracing/jaeger" \
      org.opencontainers.image.licenses="Apache-2.0"
ENV HOME=/tmp
COPY --from=build --chown=10001:0 --chmod=0555 /out/query-linux /go/bin/query-linux
USER 10001:0
EXPOSE 16685 16686 16687
ENTRYPOINT ["/go/bin/query-linux"]
