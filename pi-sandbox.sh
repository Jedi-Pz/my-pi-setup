#!/bin/bash
# pi-sandbox - Run Pi coding agent in isolated sandbox
#
# Usage:
#   ./pi-sandbox.sh                          # interactive mode
#   ./pi-sandbox.sh -p "your prompt"          # non-interactive
#   ./pi-sandbox.sh --model "claude-sonnet-4-6" -p "prompt"  # different model
#
# Config:
#   Volume pi-data: Pi config, sessions, extensions, skills (persistent)
#   Mount $PWD → /workspace (project files)

set -e

PI_DATA_VOLUME="pi-data"
PI_IMAGE="pi-sandbox"
WORKSPACE="${WORKSPACE:-$(pwd)}"

# Ensure the Git config file exists to avoid Docker creating a directory
GITCONFIG=""
if [ -f "$HOME/.gitconfig" ]; then
    GITCONFIG="-v $HOME/.gitconfig:/home/pi/.gitconfig:ro"
fi

# Use -it only when running in a real terminal (not piped/scripted)
DOCKER_FLAGS=""
if [ -t 0 ]; then
    DOCKER_FLAGS="-it"
fi

exec docker run --rm $DOCKER_FLAGS \
  --cap-drop ALL \
  --security-opt no-new-privileges=true \
  --memory 4g --cpus 2 --pids-limit 100 \
  -v "$WORKSPACE:/workspace:rw" \
  -v "${PI_DATA_VOLUME}:/home/pi/.pi" \
  $GITCONFIG \
  -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-any}" \
  -e TERM="${TERM:-xterm-256color}" \
  "$PI_IMAGE" "$@"
