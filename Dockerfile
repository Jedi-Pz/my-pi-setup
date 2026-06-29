FROM node:24-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates git ripgrep fd-find \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

RUN useradd -m -s /bin/bash pi \
    && mkdir -p /workspace \
    && chown pi:pi /workspace

USER pi
WORKDIR /workspace
ENTRYPOINT ["pi"]
