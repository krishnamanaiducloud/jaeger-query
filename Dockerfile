# syntax=docker/dockerfile:1.7
ARG BUILD_IMAGE=cgr.dev/chainguard/wolfi-base:latest@sha256:8509ee4351a2e501b7f98201f2e2642396e82020c61a589cacdcfe74b9de46c1
ARG RUNTIME_IMAGE=cgr.dev/chainguard/static:latest@sha256:fc42af33e643f20d08baf03cddcc1c02ba57052dfb02edb0d79f3fc47bcea8d9

FROM --platform=$BUILDPLATFORM ${BUILD_IMAGE} AS source
ARG JAEGER_VERSION=2.23.0
ARG JAEGER_COMMIT=d723f91447f29a345c288f37eb8d1ce7807bc0be

# apk-install is `apk add` with per-attempt timeouts, retries and a package cache, so a stalled
# or failed download is retried instead of failing the build.
COPY build/apk-install.sh /usr/local/bin/apk-install
RUN sh /usr/local/bin/apk-install bash build-base corepack curl git go gzip jq make nodejs-24 npm pnpm
ENV CGO_ENABLED=0 GOTOOLCHAIN=local
WORKDIR /src
RUN git -c advice.detachedHead=false clone --quiet --depth 1 --recurse-submodules --shallow-submodules \
      --branch "v${JAEGER_VERSION}" https://github.com/jaegertracing/jaeger.git . \
    && test "$(git rev-parse HEAD)" = "${JAEGER_COMMIT}"

FROM source AS ui
RUN make build-ui

# Upstream v2.23.0 pins Go modules with known vulnerabilities; raise them to fixed releases.
FROM ui AS patched
COPY build/patch-modules.sh /usr/local/bin/patch-modules.sh
RUN --mount=type=cache,id=jaeger-go-mod,target=/root/go/pkg/mod,sharing=locked \
    sh /usr/local/bin/patch-modules.sh

FROM patched AS build
ARG TARGETOS
ARG TARGETARCH
ARG JAEGER_VERSION=2.23.0
ARG JAEGER_COMMIT=d723f91447f29a345c288f37eb8d1ce7807bc0be
# Version information as upstream's build (scripts/makefiles/BuildInfo.mk): the release tag,
# commit and commit date, set in github.com/jaegertracing/jaeger/internal/version.
RUN --mount=type=cache,id=jaeger-go-mod,target=/root/go/pkg/mod,sharing=locked \
    --mount=type=cache,id=jaeger-go-build,target=/root/.cache/go-build,sharing=locked \
    v=github.com/jaegertracing/jaeger/internal/version \
    && date="$(TZ=UTC0 git show --quiet --date='format-local:%Y-%m-%dT%H:%M:%SZ' --format='%cd' "${JAEGER_COMMIT}")" \
    && GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" go build -trimpath -buildvcs=false \
      -ldflags "-s -w -buildid= -X ${v}.commitSHA=${JAEGER_COMMIT} -X ${v}.latestVersion=v${JAEGER_VERSION} -X ${v}.date=${date}" \
      -o /out/jaeger ./cmd/jaeger \
    && mkdir -p /out/cmd/jaeger \
    && mv /out/jaeger /out/cmd/jaeger/jaeger \
    && ln -s jaeger /out/cmd/jaeger/jaeger-linux \
    && cp cmd/jaeger/config-ui.json cmd/jaeger/sampling-strategies.json /out/cmd/jaeger/ \
    && chmod 0555 /out/cmd/jaeger/jaeger \
    && chmod 0444 /out/cmd/jaeger/config-ui.json /out/cmd/jaeger/sampling-strategies.json

FROM ${RUNTIME_IMAGE}
ARG JAEGER_VERSION=2.23.0
ARG IMAGE_VERSION=2.23.0.1-patched
LABEL org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.source="https://github.com/jaegertracing/jaeger" \
      org.opencontainers.image.licenses="Apache-2.0"
ENV JAEGER_LISTEN_HOST=0.0.0.0
WORKDIR /cmd/jaeger
# Same layout as the official jaegertracing/jaeger image: /cmd/jaeger/jaeger-linux (a link to the
# binary, for manifests that set it as the command) and the default sampling-strategies.json.
COPY --from=build --chown=10001:0 /out/cmd/jaeger/ /cmd/jaeger/
COPY --chown=10001:0 --chmod=0444 config.yaml /cmd/jaeger/config.yaml
USER 10001:0
EXPOSE 4317 4318 14250 14268 16686 8888 13133
ENTRYPOINT ["/cmd/jaeger/jaeger"]
CMD ["--config", "/cmd/jaeger/config.yaml"]

