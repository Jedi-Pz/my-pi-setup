# Pi Sandbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Pi coding agent inside a Colima + Podman container sandbox with all storage on external drive `/Volumes/Storage`.

**Architecture:** Colima Linux VM (Apple VZ.framework) on external drive via `~/.colima → /Volumes/Storage/colima/` symlink. Podman rootless inside VM. Pi runs as non-root user in a hardened container with cap-drop, read-only rootfs, and resource limits. Project files on external drive mounted via virtiofs.

**Tech Stack:** Colima 0.10.1, Podman (inside VM), node:24-bookworm-slim, @mariozechner/pi-coding-agent

## Global Constraints

- All persistent storage on `/Volumes/Storage/` (external APFS drive, 715GB)
- Zero persistent footprint on internal SSD (symlink only, ~50 bytes)
- macOS Apple Silicon (arm64), 16GB RAM
- Colima VM: 4 vCPUs, 6GB RAM, 60GB sparse disk
- Pi container: 2 CPUs, 4GB mem, pids-limit 100
- Non-root user inside container
- Colima already installed (0.10.1), ~/.colima exists with _lima/_store, podman NOT installed

---
