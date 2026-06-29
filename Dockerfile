# Pi coding agent sandbox
# ========================
#
# This builds a container image for running Pi with security hardening.
# The image itself is portable — no personal paths or credentials baked in.
#
# What YOU need to configure for your machine:
#
#   1. colima.yaml mounts
#      Pi accesses host directories via virtiofs. Add the paths you want
#      Pi to work in:
#        mounts:
#          - location: "<your-project-drive>"  # e.g. /Volumes/Data
#            writable: true
#          - location: "~"                     # home dir (quotes required!)
#            writable: true
#
#   2. pi-sandbox.sh
#      The launch script mounts $PWD → /workspace (the directory you run
#      `pi` from becomes the container's working directory). If you want
#      a fixed project path instead, set WORKSPACE before running.
#
#   3. models.json (inside the pi-data Docker volume)
#      Points Anthropic to your local proxy. See cookbook/02-model-config.md.
#
# Build:  docker build -t pi-sandbox .
# Run:    ./pi-sandbox.sh          (or: alias pi="path/to/pi-sandbox.sh")

FROM node:24-bookworm-slim

# System dependencies: git for version control, ripgrep + fd for file search
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates git ripgrep fd-find \
    && rm -rf /var/lib/apt/lists/*

# Pi coding agent (Anthropic-compatible, connects via local proxy)
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# Non-root user. /workspace is the bind-mount target for your host directory.
RUN useradd -m -s /bin/bash pi \
    && mkdir -p /workspace \
    && chown pi:pi /workspace

USER pi
WORKDIR /workspace
ENTRYPOINT ["pi"]
