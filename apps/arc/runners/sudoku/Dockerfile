FROM ghcr.io/actions/actions-runner:latest

RUN sudo apt-get update \
    && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential curl wget \
    && sudo rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sudo sh -s -- -y --no-modify-path \
    && sudo /root/.cargo/bin/rustup default stable

RUN echo "PATH=/root/.cargo/bin:${PATH}" >> /etc/environment
