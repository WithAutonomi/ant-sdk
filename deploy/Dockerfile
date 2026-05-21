# antd container image for the Autonomi daemon.
#
# Built from the per-platform binaries produced earlier in the same Release
# workflow (antd-linux-amd64, antd-linux-arm64). Both files sit in the build
# context; buildx's TARGETARCH picks the matching one at COPY time.
#
# Defaults to binding 0.0.0.0 on both REST + gRPC via ANTD_REST_ADDR /
# ANTD_GRPC_ADDR env vars — antd's own default is loopback-only as of
# v0.8.0 (#107), but a container is useless without external reachability.
# Override at run time with `-e ANTD_REST_ADDR=127.0.0.1:8082` or by
# passing `--rest-addr` after the image name.
#
# Build manually for local smoke test:
#   docker buildx build \
#     --platform linux/amd64,linux/arm64 \
#     -f deploy/Dockerfile \
#     -t withautonomi/antd:dev \
#     deploy/

FROM alpine:3.21

ARG TARGETOS=linux
ARG TARGETARCH=amd64

RUN apk add --no-cache ca-certificates wget tzdata \
 && addgroup -g 65532 -S antd \
 && adduser -u 65532 -S -G antd -h /var/lib/antd -s /sbin/nologin antd \
 && mkdir -p /var/lib/antd \
 && chown -R antd:antd /var/lib/antd

# Copy the binary matching this layer's TARGETOS/TARGETARCH. buildx provides
# both files in the build context and selects per-platform automatically.
COPY antd-${TARGETOS}-${TARGETARCH} /usr/local/bin/antd
RUN chmod +x /usr/local/bin/antd

USER antd
WORKDIR /var/lib/antd
VOLUME ["/var/lib/antd"]

EXPOSE 8082 50051

# Container-default network reachability. antd has no built-in auth so this
# is an opt-in (overrideable) — anyone running the image is presumed to be
# fronting it with their own gateway / firewall / reverse proxy.
ENV ANTD_REST_ADDR=0.0.0.0:8082
ENV ANTD_GRPC_ADDR=0.0.0.0:50051

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8082/health || exit 1

ENTRYPOINT ["antd"]
