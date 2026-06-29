# My Pi Setup

Pi coding agent sandbox running in a Colima VM + Docker container on macOS (Apple Silicon).

## Quickstart

```bash
# One-time setup
brew install colima docker
colima start --vm-type=vz --vz-rosetta --cpu 4 --memory 6 --disk 60
docker build -t pi-sandbox .

# Use
./pi-sandbox.sh              # interactive mode
./pi-sandbox.sh --continue   # resume previous session
./pi-sandbox.sh -p "..."     # non-interactive, single prompt
```

## Files

- `Dockerfile` — Pi container image (Node 24 + pi 0.80.2 + git + ripgrep + fd)
- `pi-sandbox.sh` — Launch script (cap-drop ALL, resource limits, persistent volume)
- `docs/` — Design specs and implementation plans
- `sandbox-research-report.md` — Survey of 12 sandbox technologies for AI agent isolation

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
