# syntax=docker/dockerfile:1.7
ARG BUILD_IMAGE=cgr.dev/chainguard/wolfi-base:latest@sha256:fd50bd0cdeb808cf4f45c9c9189e0cc7f7fcc27195d69abd6622c80527e7e021
ARG RUNTIME_IMAGE=cgr.dev/chainguard/static:latest@sha256:fc42af33e643f20d08baf03cddcc1c02ba57052dfb02edb0d79f3fc47bcea8d9

FROM --platform=$BUILDPLATFORM ${BUILD_IMAGE} AS build
ARG TARGETOS
ARG TARGETARCH
ARG JAEGER_VERSION=2.22.0
ARG JAEGER_COMMIT=462bb49fcff9af4be9556bf0206d07f5171bd8d7

RUN apk add --no-cache bash build-base corepack curl git go gzip jq make nodejs-24 npm pnpm
ENV CGO_ENABLED=0 GOTOOLCHAIN=local
WORKDIR /src
RUN git -c advice.detachedHead=false clone --quiet --depth 1 --recurse-submodules --shallow-submodules \
      --branch "v${JAEGER_VERSION}" https://github.com/jaegertracing/jaeger.git . \
    && test "$(git rev-parse HEAD)" = "${JAEGER_COMMIT}"
RUN --mount=type=cache,id=jaeger-go-mod,target=/root/go/pkg/mod,sharing=locked \
    --mount=type=cache,id=jaeger-go-build,target=/root/.cache/go-build,sharing=locked \
    make build-ui \
    && GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" go build -trimpath -buildvcs=false \
      -ldflags "-s -w -buildid= -X github.com/jaegertracing/jaeger/pkg/version.commitSHA=${JAEGER_COMMIT} -X github.com/jaegertracing/jaeger/pkg/version.latestVersion=v${JAEGER_VERSION}" \
      -o /out/jaeger ./cmd/jaeger \
    && /out/jaeger version

FROM ${RUNTIME_IMAGE}
ARG JAEGER_VERSION=2.22.0
LABEL org.opencontainers.image.version="${JAEGER_VERSION}-patched" \
      org.opencontainers.image.source="https://github.com/jaegertracing/jaeger" \
      org.opencontainers.image.licenses="Apache-2.0"
ENV JAEGER_LISTEN_HOST=0.0.0.0
WORKDIR /cmd/jaeger
COPY --from=build --chown=10001:0 --chmod=0555 /out/jaeger /cmd/jaeger/jaeger
COPY --from=build --chown=10001:0 --chmod=0444 /src/cmd/jaeger/config-ui.json /cmd/jaeger/config-ui.json
COPY --chown=10001:0 --chmod=0444 config.yaml /cmd/jaeger/config.yaml
USER 10001:0
EXPOSE 4317 4318 14250 14268 16686 8888 13133
ENTRYPOINT ["/cmd/jaeger/jaeger"]
CMD ["--config", "/cmd/jaeger/config.yaml"]

