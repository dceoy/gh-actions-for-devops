# syntax=docker/dockerfile:1
ARG GO_VERSION=1.24
FROM public.ecr.aws/docker/library/golang:${GO_VERSION} AS builder

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

RUN \
      --mount=type=bind,source=.,target=/mnt/host \
      cp -a /mnt/host /opt/build_readme_md

WORKDIR /opt/build_readme_md

RUN \
      --mount=type=cache,target=/go/pkg/mod \
      --mount=type=cache,target=/root/.cache/go-build \
      go mod download \
      && go build -o build_readme_md build_readme_md.go

FROM public.ecr.aws/docker/library/golang:${GO_VERSION} AS base

COPY --from=builder /opt/build_readme_md /app

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

HEALTHCHECK NONE

ENTRYPOINT ["/app/build_readme_md"]
