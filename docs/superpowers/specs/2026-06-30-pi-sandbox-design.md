# Pi Coding Agent Sandbox: Implementation Design

**Date:** 2026-06-30
**Status:** Approved
**Goal:** Run Pi coding agent in an isolated sandbox on macOS Apple Silicon (16GB RAM, 256GB SSD), with all persistent storage on external drive (`/Volumes/Storage`), zero footprint on internal SSD.

---

## 1. Architecture Overview

```
macOS host (Apple Silicon, 16GB RAM)
  │
  │  ~/.colima → /Volumes/Storage/colima/   (symlink, 0 bytes on internal SSD)
  │
  └── Colima Linux VM (Apple Virtualization.framework, 4 vCPUs, 6GB RAM)
       │  VM disk: /Volumes/Storage/colima/default/diffdisk
       │
       └── Podman rootless container engine
            │  All images, layers, volumes stored inside VM disk
            │
            └── Pi Agent Container
                 │  Image: node:24-bookworm-slim + @mariozechner/pi-coding-agent
                 │  Mounts:
                 │    - /Volumes/Storage/Project → /workspace (bind mount)
                 │    - pi-data volume → /home/pi/.pi (named volume, in VM disk)
                 │  Env: ANTHROPIC_API_KEY, TERM
                 │  Caps: --cap-drop ALL, --no-new-privileges
                 │  Resources: 4GB mem, 2 CPUs, pids-limit 100
```

## 2. Storage Layout

```
/Volumes/Storage/                        ← External drive (715GB, APFS)
├── colima/                              ← Colima home (symlinked from ~/.colima)
│   └── default/
│       ├── diffdisk                      ← VM sparse disk (grows as needed)
│       └── ...                           ← VM config, socket, logs
├── Project/
│   └── pi-study/                         ← Project workspace (already exists)
│       ├── docs/
│       ├── sandbox-research-report.md
│       └── ...                           ← git repo will be initialized here
│
~/.colima → /Volumes/Storage/colima/     ← Symlink (internal SSD: ~50 bytes)

Internal SSD usage:
  - ~/.colima symlink: negligible
  - Colima socket files (runtime only): /tmp/colima-*.sock, cleaned on stop
  - Nothing else. Zero persistent storage on internal SSD.
```

## 3. Component Details

### 3.1 Colima Linux VM

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| `--vm-type` | `vz` | Apple Virtualization.framework, native aarch64, best perf |
| `--cpu` | `4` | Half of 8 cores total, safe for host |
| `--memory` | `6` | Leaves 10GB for macOS host |
| `--disk` | `60` | Sparse file, won't use all at once. Room for images + volumes |
| `--vz-rosetta` | yes | Enables x86_64 → aarch64 translation if needed |
| `--mount` | `/Volumes/Storage/Project:w` | virtiofs mount for project files |
| COLIMA_HOME | `/Volumes/Storage/colima` | Via symlink ~/.colima |

### 3.2 Podman Configuration

Podman runs inside the Colima VM (colima auto-configures it). Key behaviors:

- Rootless by default inside the VM (container user mapped to VM user)
- Docker CLI compatible: `alias docker=podman` or use `podman` directly
- Images stored in VM disk (overlay2 on XFS/ext4 inside VM)
- Named volumes in VM disk
- `--network slirp4netns` for rootless NAT networking

### 3.3 Pi Container Image

```dockerfile
FROM node:24-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates git ripgrep fd-find
RUN npm install -g --ignore-scripts @mariozechner/pi-coding-agent
RUN useradd -m -s /bin/bash pi && mkdir -p /workspace && chown pi:pi /workspace
USER pi
WORKDIR /workspace
ENTRYPOINT ["pi"]
```

### 3.4 Runtime Configuration

```bash
podman run --rm -it \
  --name pi-agent \
  --cap-drop ALL --no-new-privileges \
  --read-only --tmpfs /tmp:noexec \
  --memory 4g --cpus 2 --pids-limit 100 \
  --network slirp4netns \
  -v "$PWD:/workspace" \
  -v "pi-data:/home/pi/.pi" \
  -v "$HOME/.gitconfig:/home/pi/.gitconfig:ro" \
  -e ANTHROPIC_API_KEY \
  -e TERM="$TERM" \
  pi-sandbox
```

## 4. Storage Validation Strategy

After setup, verify zero internal SSD consumption:

```bash
# Check that ~/.colima is a symlink to external drive
ls -la ~/.colima
# → ~/.colima -> /Volumes/Storage/colima/

# Check Colima VM disk location
ls -lh /Volumes/Storage/colima/default/diffdisk

# Verify no large files on internal SSD
du -sh ~/.colima 2>/dev/null  # should be negligible or resolve to external
```

## 5. Phased Implementation

### Phase 1: Environment Setup (~30min)
- [ ] Create `/Volumes/Storage/colima/` directory
- [ ] Create symlink `~/.colima → /Volumes/Storage/colima/`
- [ ] Install colima: `brew install colima podman`
- [ ] Start Colima with optimized parameters
- [ ] Verify VM disk is on external drive
- [ ] Test basic podman commands

### Phase 2: Pi Container Build (~15min)
- [ ] Write Dockerfile (in project dir on external drive)
- [ ] Build image: `podman build -t pi-sandbox .`
- [ ] Verify image stored in VM disk (external drive)

### Phase 3: Pi Runtime Test (~30min)
- [ ] Run Pi interactively in sandbox
- [ ] Verify Pi can read/write project files
- [ ] Test all Pi tools: read, write, edit, bash, grep
- [ ] Verify API connectivity (LLM provider)
- [ ] Verify TUI renders correctly

### Phase 4: Hardening (~30min)
- [ ] Test capability dropping (--cap-drop ALL)
- [ ] Test read-only rootfs
- [ ] Test resource limits (verify enforcement)
- [ ] Document what breaks and what works

### Phase 5: Verification (~15min)
- [ ] Run storage validation (confirm zero internal SSD)
- [ ] Test container restart persists Pi config
- [ ] Test session persistence

## 6. What's NOT in Scope

- **macOS Seatbelt sandbox-exec**: Deferred. Adds kernel-level filesystem allowlisting. Explored in Phase 4 of research plan after basic container is working.
- **Windows WSL2 + Bubblewrap**: Deferred to separate implementation on the secondary machine.
- **Network domain allowlisting (iptables)**: Deferred. Phase 3 of research plan.
- **Gondolin microVM pattern**: Deferred. Needs separate investigation on Apple Silicon compatibility.
- **Production hardening**: This is a development/learning setup, not a production deployment.

## 7. Risk Notes

- **Colima VM 6GB + container 4GB + macOS = ~10GB baseline**: Leaves 6GB headroom on 16GB system. Colima's memory is shared-page, so actual usage may be lower.
- **VM disk file is sparse**: 60GB allocation, actual usage starts ~2-3GB and grows as images/layers are pulled.
- **virtiofs on external drive**: Performance will be limited by external drive speed. APFS over USB-C/Thunderbolt should be fine for an AI coding agent (I/O is not the bottleneck).
- **Colima socket in /tmp**: Runtime socket file lives on internal SSD. ~few KB. Acceptable.
- **`sandbox-exec` deprecation**: Not blocking since we're deferring Seatbelt. If Apple removes `sandbox-exec` before we explore it, alternatives exist (AppSandbox entitlements, or rely on the Colima VM boundary alone).
