ARG GOMPLATE_VERSION=3.11.6

# Download on the builder's native architecture. TARGETOS and TARGETARCH select
# the release binary copied into the target image.
FROM --platform=$BUILDPLATFORM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS gomplate-download
ARG GOMPLATE_VERSION
ARG TARGETOS
ARG TARGETARCH

COPY build/gomplate/checksums/ /checksums/
RUN set -eu; \
    target_os="${TARGETOS:-linux}"; \
    target_arch="${TARGETARCH:-}"; \
    if [ -z "${target_arch}" ]; then \
      case "$(uname -m)" in \
        x86_64) target_arch=amd64 ;; \
        aarch64) target_arch=arm64 ;; \
        *) target_arch="$(uname -m)" ;; \
      esac; \
    fi; \
    case "${target_os}/${target_arch}" in \
      linux/amd64|linux/arm64) ;; \
      *) echo "unsupported target platform ${target_os}/${target_arch}; supported platforms: linux/amd64, linux/arm64" >&2; exit 1 ;; \
    esac; \
    artifact="gomplate_${target_os}-${target_arch}"; \
    checksum_file="/checksums/gomplate-v${GOMPLATE_VERSION}-${target_os}-${target_arch}.sha256"; \
    if [ ! -f "${checksum_file}" ]; then \
      echo "no committed checksum for gomplate v${GOMPLATE_VERSION} on ${target_os}/${target_arch}" >&2; \
      exit 1; \
    fi; \
    apk --no-cache add ca-certificates; \
    mkdir /download; \
    cd /download; \
    wget -q "https://github.com/hairyhenderson/gomplate/releases/download/v${GOMPLATE_VERSION}/${artifact}"; \
    sha256sum -c "${checksum_file}"; \
    mv "${artifact}" gomplate; \
    chmod 0755 gomplate

FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b
ARG GOMPLATE_VERSION

# ca-certificates retains Gomplate's HTTPS data-source support. Alpine's
# BusyBox supplies find, dirname, mkdir, and the other utilities used by the
# generation script.
RUN apk --no-cache add bash ca-certificates \
    && mkdir /gatekeeper-library
COPY --from=gomplate-download /download/gomplate /usr/local/bin/gomplate

LABEL org.opencontainers.image.title="Gatekeeper library template generator" \
      org.opencontainers.image.version="${GOMPLATE_VERSION}"

WORKDIR /gatekeeper-library
ENTRYPOINT ["/bin/bash"]
