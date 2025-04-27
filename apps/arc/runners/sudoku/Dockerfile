FROM ghcr.io/actions/actions-runner:latest

RUN sudo apt-get update \
    && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential curl wget \
    && sudo rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path \
    && /home/runner/.cargo/bin/rustup default stable

RUN echo "/home/runner/.cargo" >> /home/runner/.path
RUN echo 'export PATH="${PATH}:$(cat /home/runner/.path)"' >> /home/runner/.bashrc
