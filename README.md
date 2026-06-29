# My Pi Setup

Pi coding agent sandbox running in a Colima VM + Docker container on macOS (Apple Silicon).

## Quickstart

```bash
# 1. Install prerequisites
brew install colima docker

# 2. Start Colima (edit mounts to match your setup)
colima start --vm-type=vz --vz-rosetta --cpu 4 --memory 6 --disk 60

# 3. Ensure these mounts are in colima.yaml (add if missing):
#    mounts:
#      - location: "<your-project-drive>"   # external drive, if any
#        writable: true
#      - location: "~"
#        writable: true

# 4. Build Pi container image
docker build -t pi-sandbox .

# 5. Add alias to ~/.zshrc
#    alias pi="<path-to-this-repo>/pi-sandbox.sh"

# Use
pi                          # interactive mode
pi --continue               # resume previous session
pi -p "..." --no-session    # one-shot, ephemeral

## Files

- `Dockerfile` — Pi container image (Node 24 + pi 0.80.2 + git + ripgrep + fd)
- `pi-sandbox.sh` — Launch script (cap-drop ALL, resource limits, persistent volume)
- `cookbook/` — Setup guides and configuration notes

## Architecture

```
macOS host → Colima Linux VM (VZ.framework, on external drive)
  → Docker container (cap-drop ALL, 4GB mem, 2 CPU)
    → Pi coding agent
```

All storage on external drive. Internal SSD: zero persistent footprint.

## Model Config

`models.json` redirects Anthropic to local proxy (`cc-switch` on `host.docker.internal:15721`), using the same Claude model (claude-opus-4-8) as the host Claude Code.

## Upgrading

```bash
docker build --no-cache -t pi-sandbox .
```
