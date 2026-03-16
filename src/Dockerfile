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
      && go build -o /usr/local/bin/build_readme_md .

FROM public.ecr.aws/docker/library/golang:${GO_VERSION} AS base

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

RUN \
      groupadd --system app \
      && useradd --system --gid app --home-dir /app --shell /usr/sbin/nologin app

COPY --from=builder --chown=app:app /usr/local/bin/build_readme_md /app/build_readme_md

HEALTHCHECK NONE

USER app

ENTRYPOINT ["/app/build_readme_md"]
