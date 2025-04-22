FROM ghcr.io/actions/actions-runner:latest

RUN sudo apt-get update \
    && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential wget \
    && sudo rm -rf /var/lib/apt/lists/*
