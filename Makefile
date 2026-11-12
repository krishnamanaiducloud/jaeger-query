.PHONY: build smoke compatibility scan sbom builder push all
IMAGENAME=mohankrishna999/jaeger-query
VERSION=1.65.0.1-patched
PLATFORMS=linux/amd64,linux/arm64
BUILDER=securebridge
TRIVY_IMAGE=aquasec/trivy:0.76.2
GRYPE_IMAGE=anchore/grype:v0.121.3
SYFT_IMAGE=anchore/syft:v1.57.1
build:
	docker buildx build --load --platform linux/amd64 -t ${IMAGENAME}:${VERSION} .
smoke: build
	docker run --rm ${IMAGENAME}:${VERSION} version
compatibility: build
	sh tests/verify-cli-contract.sh ${IMAGENAME}:${VERSION}
scan: build
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache/trivy ${TRIVY_IMAGE} image --scanners vuln --pkg-types os,library --severity UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL --ignore-unfixed=false --exit-on-eol 1 --exit-code 1 ${IMAGENAME}:${VERSION}
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v grype-cache:/.cache/grype ${GRYPE_IMAGE} docker:${IMAGENAME}:${VERSION} --fail-on negligible
sbom: build
	mkdir -p sbom
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock ${SYFT_IMAGE} docker:${IMAGENAME}:${VERSION} -o spdx-json > sbom/jaeger-query-${VERSION}.spdx.json
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock ${SYFT_IMAGE} docker:${IMAGENAME}:${VERSION} -o cyclonedx-json > sbom/jaeger-query-${VERSION}.cdx.json
builder:
	docker buildx inspect ${BUILDER} >/dev/null 2>&1 || docker buildx create --name ${BUILDER} --driver docker-container >/dev/null
push: builder
	docker buildx build --builder ${BUILDER} --platform ${PLATFORMS} --provenance=false --sbom=false -t ${IMAGENAME}:${VERSION} --push .
all: compatibility scan sbom

