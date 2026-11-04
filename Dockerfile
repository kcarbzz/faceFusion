FROM python:3.12

ARG FACEFUSION_VERSION=3.9.2
ENV PIP_BREAK_SYSTEM_PACKAGES=1

WORKDIR /facefusion

RUN apt-get update && apt-get install -y --no-install-recommends curl ffmpeg git \
 && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/facefusion/facefusion.git --branch ${FACEFUSION_VERSION} --single-branch . \
 && python install.py default --skip-conda
