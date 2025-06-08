# syntax=docker/dockerfile:1
ARG PYTHON_VERSION=3.13
FROM public.ecr.aws/docker/library/python:${PYTHON_VERSION}-slim AS base

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONIOENCODING=utf-8
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PIP_NO_CACHE_DIR=1

RUN \
      --mount=type=bind,source=.,target=/mnt/host \
      cp -a /mnt/host /tmp/build_readme_md

RUN \
      --mount=type=cache,target=/root/.cache \
      /usr/local/bin/pip install -U uv \
      && uv build --directory /tmp/build_readme_md \
      && pip install -U /tmp/build_readme_md/dist/*.whl

WORKDIR /root

HEALTHCHECK NONE

ENTRYPOINT ["python"]
