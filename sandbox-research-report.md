# Pi Coding Agent Sandboxed Execution: Comprehensive Research Report

**Date:** 2026-06-30
**Goal:** Determine the best approach to run the Pi coding agent in a secure, isolated sandbox on the user's machines (macOS Apple Silicon primary, Windows x86_64 secondary, accessible via SSH).

---

## 1. Executive Summary

Pi is a powerful LLM-powered coding agent with no built-in sandboxing -- it inherits the full permissions of the process that launches it. Running it unsandboxed means the agent (and any code it generates or executes via its `bash` tool) can read/write any file, make arbitrary network calls, and exhaust system resources. The user wants to "折腾一下" (tinker/experiment) -- security matters but the primary goal is understanding the technology and getting something functional.

**CubeSandbox (Tencent's open-source MicroVM sandbox)**, despite being the most secure option with hardware-level KVM isolation and sub-60ms cold starts, **cannot practically run on macOS or Windows**. It requires a Linux host with KVM, XFS filesystem, and x86_64 architecture -- none of which are available natively on Apple Silicon macOS. Workarounds involving nested virtualization are unsupported and would perform terribly.

**The recommended approach** is defense-in-depth using the platform's native isolation primitives: on macOS, a **Lima/Colima Linux VM** running Podman (rootless containers), with the agent process further constrained by **macOS Seatbelt (sandbox-exec)** profiles for explicit filesystem and network allowlisting. On Windows, **WSL2** provides a Linux VM boundary, inside which **Bubblewrap (bwrap)** can provide per-command namespace isolation. This gives strong practical isolation without introducing unresolvable platform compatibility issues.

---

## 2. CubeSandbox Analysis

### 2.1 What Is CubeSandbox?

CubeSandbox is an open-source (Apache 2.0) secure sandbox service built by Tencent Cloud, designed specifically for AI agent code execution. It was open-sourced on April 20, 2026. It provides hardware-level isolation via KVM MicroVMs -- each sandbox gets its own Linux kernel, unlike Docker containers which share the host kernel. It achieves sub-60ms cold starts (via snapshot restore), under 5MB memory overhead per instance, and supports 2,000+ sandboxes per physical server.

It powered Tencent's internal serverless platform (billions of daily invocations) and Yuanbao (Tencent's AI assistant). After migrating Yuanbao's AI coding scenario to CubeSandbox, Tencent reported a 95.8% reduction in resource core-hour consumption.

The architecture spans a Control Plane (REST API in Rust, orchestrator in Go, Redis for metadata) and a Data Plane (per-node lifecycle agent, containerd shim, RustVMM-based hypervisor, eBPF virtual switch, CoW storage engine, and L7 egress proxy). It is E2B SDK-compatible, allowing existing E2B code to migrate by changing a single URL.

- **GitHub:** https://github.com/TencentCloud/CubeSandbox
- **Stars:** ~6,600 (in ~10 weeks)
- **Latest release:** v0.4.0 (June 15, 2026)
- **Maturity:** Pre-1.0, but production-proven internally at Tencent scale. Rapid release cadence (~17 releases in 8 weeks).

### 2.2 Can It Run on the User's Machines?

**macOS Apple Silicon: No.**

The hard blockers are:

1. **KVM dependency.** CubeSandbox requires `/dev/kvm`, a Linux kernel subsystem. macOS does not have KVM. Apple's Hypervisor.framework is not supported by CubeSandbox.

2. **x86_64 binary requirement.** All compiled components (Rust, Go, C) are x86_64. There is no aarch64 build in any GitHub release. Running x86_64 binaries under Rosetta inside a Linux VM on Apple Silicon means triple emulation (Rosetta translation -> aarch64 Linux -> x86_64 binaries -> KVM MicroVMs) -- not viable.

3. **XFS filesystem requirement.** CubeSandbox mandates XFS with reflink support at `/data/cubelet` for its Copy-on-Write storage engine. macOS does not support XFS.

4. **No supported path.** The dev-environment documentation lists only three host options: WSL 2 on Windows, Linux physical machine, and Linux VM with nested virtualization. macOS is not mentioned anywhere.

**Windows x86_64: Partially, via WSL 2 only.**

The documented "development / evaluation" path is WSL 2 on Windows 11 22H2+ with nested virtualization enabled. This means:
- The user needs Windows 11 22H2 or newer (user qualifies with an x86_64 Windows machine).
- WSL nested virtualization must be enabled (requires specific CPU + BIOS settings).
- CubeSandbox runs inside the WSL 2 Linux VM.
- This is explicitly labeled as "development / evaluation" -- not production.

There is no native Windows support (no Windows binaries, no Hyper-V backend).

**Linux (x86_64): Yes, full support.**

This is the only fully supported platform. Requirements: x86_64 CPU, KVM, glibc >= 2.31, XFS at `/data/cubelet`, >= 8GB RAM, >= 50GB disk.

### 2.3 Feasibility Verdict

CubeSandbox is a server-side technology. It is not a viable option for a developer who wants to sandbox Pi on a laptop or desktop, especially not on macOS Apple Silicon. The one-click installer assumes a dedicated x86_64 Linux server with root access and XFS storage. Provisioning a cloud VM just to sandbox Pi would be the most practical path, but defeats the purpose of local experimentation.

**CubeSandbox should be ruled out for this use case.** It is interesting technology to understand, and worth revisiting if the user ever deploys Pi as a hosted multi-tenant service, but it is not the right tool for local sandboxing on macOS or Windows.

---

## 3. Alternative Solutions Comparison

Twelve isolation technologies were evaluated against the specific requirements of sandboxing Pi on macOS Apple Silicon and Windows x86_64.

### 3.1 Comparison Matrix (Scored for This Use Case)

| # | Solution | macOS AS Support | Windows Support | Isolation Level | Setup Complexity | Security Rating | Resource Overhead | Filesystem Control | Pi Fit |
|---|----------|-----------------|----------------|----------------|-----------------|----------------|-------------------|-------------------|--------|
| 1 | **Docker (hardened)** | Via Colima/OrbStack/DD | Via Docker Desktop/WSL2 | Kernel namespaces | Low-Medium | 5/10 (out of box), 8/10 (hardened) | 150MB+ daemon | Bind mounts | Good |
| 2 | **Podman (rootless)** | Via `podman machine` | Via WSL2 | Kernel namespaces, no daemon | Low-Medium | 7/10 | ~50MB baseline | Bind mounts | Best container |
| 3 | **Firecracker** | No (Linux VM needed) | No (Linux VM needed) | Hardware microVM | High | 10/10 | ~5MB per microVM | Manual (virtio-fs) | Overkill, impractical |
| 4 | **gVisor** | No (Linux VM needed) | No (WSL2 needed) | User-space kernel (Go) | Medium | 8/10 | 10-50MB per sandbox | Gofer-mediated | Middle-ground, Linux only |
| 5 | **Kata Containers** | No (Linux VM needed) | No (WSL2 needed) | Hardware VM per container | High | 9/10 | 10-20MB per VM | virtio-fs | Server-scale only |
| 6 | **Lima/Colima** | **Native (VZ.framework)** | Not applicable | VM boundary | Very Easy | 7/10 (VM + containers) | 1-4GB for VM | virtiofs mounts | Excellent foundation |
| 7 | **QEMU/KVM microVMs** | Via QEMU+HVF | Via QEMU+WHPX | Hardware VM | High | 9/10 | 50-200MB per VM | virtio-fs/9p | Too complex |
| 8 | **Bubblewrap (bwrap)** | No (Linux-only) | No (WSL2 needed) | Linux namespaces+seccomp | Very Easy (on Linux) | 7/10 | 2-5MB per sandbox | Explicit bind mounts | Excellent for Linux |
| 9 | **LXC/LXD** | No (Linux VM needed) | No (WSL2 needed) | System containers | Medium | 6/10 | 50-200MB per container | Bind mounts | Overkill for agent |
| 10 | **Wine/Proton** | Not applicable | Not applicable | None | N/A | 1/10 | N/A | N/A | NOT a sandbox |
| 11 | **macOS Seatbelt** | **Native** | Not applicable | MAC kernel framework | Medium | 8/10 | Negligible | Rule-based allow/deny | Best macOS native |
| 12 | **Windows Sandbox/Hyper-V** | Not applicable | **Native** (Pro/Enterprise) | Hardware VM | Low (WS), Med (HC) | 8/10 | 1-2GB per session | Minimal or SMB | Best Windows native |

### 3.2 Supplemental: Hardening Layers (Applicable Across Solutions)

These are not standalone solutions but hardening techniques that can be layered:

| Technique | What It Does | Where It Applies |
|-----------|-------------|-----------------|
| **Capability dropping** | `--cap-drop ALL --cap-add NET_BIND_SERVICE` only | Docker/Podman |
| **`--no-new-privileges`** | Prevents setuid binaries from escalating | Docker/Podman |
| **`--read-only` rootfs** | Container filesystem is immutable | Docker/Podman |
| **`--security-opt no-new-privileges`** | Blocks privilege escalation | Docker/Podman |
| **`--security-opt seccomp=<profile>`** | Custom syscall whitelist | Docker/Podman |
| **`--tmpfs /tmp:noexec`** | Writable temp space but no executables | Docker/Podman |
| **`--pids-limit 50`** | Fork bomb protection | Docker/Podman |
| **`--memory`, `--cpus`** | Resource limits via cgroups | Docker/Podman |
| **`--network none`** | Complete network isolation | Docker/Podman |
| **User namespace remapping** | Container root != host root | Docker/Podman |

### 3.3 Why Not Firecracker/Kata/gVisor on Desktop?

These technologies are excellent for server deployments but are impractical for local development on non-Linux hosts for the same reasons as CubeSandbox (KVM dependency). On macOS, they require a Linux VM, creating a double-virtualization situation that is complex to set up and introduces significant performance penalties. On Windows, WSL2 provides a Linux VM boundary, but the complexity of managing VMMs, kernel images, and networking inside an already-virtualized environment makes these solutions unfriendly for the "tinker and learn" goal.

---

## 4. Pi Agent Containerization Requirements

### 4.1 Package and Installation

- **Package:** `@mariozechner/pi-coding-agent` (formerly `@earendil-works/pi-coding-agent`)
- **Repo:** github.com/badlogic/pi-mono (MIT license)
- **One-liner install:** `curl -fsSL https://pi.dev/install.sh | sh`
- **npm install:** `npm install -g --ignore-scripts @mariozechner/pi-coding-agent`
- **Latest release:** v0.80.2 (June 23, 2026), 240+ total releases
- **Node.js requirement:** >= 20.6.0 (recommend Node 24 LTS for extension compatibility)

### 4.2 State Directory: `~/.pi/agent/`

This directory must be persisted across container restarts. Key contents:

```
~/.pi/agent/
  auth.json           # API keys + OAuth tokens (0600, gitignored)
  settings.json        # Provider, model, thinking level, packages
  models.json          # Custom provider/model definitions
  AGENTS.md / CLAUDE.md  # Global context
  sessions/            # JSONL session files
  extensions/          # TypeScript extension modules
  skills/              # Agent Skills packages
  prompts/             # Reusable prompt templates
  themes/              # UI themes
  keybindings.json     # Custom keyboard shortcuts
  trust.json           # Project-level trust decisions
```

Override via env vars: `PI_CODING_AGENT_DIR`, `PI_CODING_AGENT_SESSION_DIR`, `PI_PACKAGE_DIR`.

### 4.3 Environment Variables

**API keys (provider-dependent):** `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `DEEPSEEK_API_KEY`, `GEMINI_API_KEY`, `MISTRAL_API_KEY`, `GROQ_API_KEY`, and ~20 more. Credentials can alternatively be stored in `~/.pi/agent/auth.json` with `!command` execution support for macOS Keychain/1Password.

**Configuration:** `PI_OFFLINE` (disable all startup network), `PI_SKIP_VERSION_CHECK`, `PI_TELEMETRY`, `PI_CACHE_RETENTION`.

### 4.4 Network Requirements

- **LLM provider APIs:** HTTPS/443 to provider endpoints (varies by model choice)
- **pi.dev:** Version check and install telemetry (suppressible via env vars)
- **npm registry:** For package installation/updates
- **OAuth callbacks:** Local servers on ports 53692 (Anthropic) and 1455 (OpenAI Codex)
- **Git:** Cloning repos for code operations

### 4.5 TTY Requirements

Pi requires a TTY for its interactive TUI. Use `docker run -it` for interactive use. For headless/automated use, Pi supports:
- `-p`/`--print` -- non-interactive, prints to stdout
- `--mode json` -- JSON events on stdout
- `--mode rpc` -- JSONL protocol over stdin/stdout
- `--no-session` -- ephemeral mode

### 4.6 Filesystem Access

Pi's tools (`read`, `write`, `edit`, `bash`, `grep`, `find`, `ls`) operate on all files accessible to the process. **No built-in permission system exists.** The agent inherits the full permissions of the user/process that launched it. This is the fundamental reason sandboxing is necessary.

Directories Pi needs:
- Project source code (read/write, must persist)
- `~/.pi/agent/` (read/write, must persist)
- `~/.gitconfig` (read, for git identity)

### 4.7 System Dependencies

- `git` (commits, package management)
- `ripgrep` (`rg`) -- documented as required
- `fd-find` (`fd`) -- commonly needed
- Standard POSIX: `bash`, `ls`, `find`, `grep`
- `node` and `npm`/`npx`

### 4.8 Security Gotchas

1. **API keys enter the container** in the Plain Docker pattern. Mitigate via Docker secrets, env vars from a `.env` file mounted read-only, or macOS Keychain integration.
2. **`bash` tool is unrestricted shell access** -- can run any command reachable in the container's PATH.
3. **No permission prompts in `-p` mode** -- project trust is skipped unless `-a`/`--approve` is passed.
4. **OAuth `/login` requires a browser and callback port reachability.**
5. **CVE-2026-54327** (fixed in v0.78.1): TOCTOU race in `auth.json` writes.
6. **`pi update --self`** reinstalls globally, which is meaningless in ephemeral containers.

### 4.9 Existing Community Docker Images

Nine community Docker projects exist, ranging from simple wrappers to 6-layer hardened sandboxes. Key examples:

| Project | Approach | Notable Features |
|---------|----------|-----------------|
| `hpoeckl/pi-coding-agent-docker` | `cpi` wrapper, Alpine | tmpfs RAM disk for `$HOME`, UID/GID matching, read-only host mounts |
| `combust-labs/pi-docker` | Build from source | RPC HTTP server mode, pre-installed Bun/pnpm/uv |
| `gni/pi-coding-agent-container` | 6-layer hardened | SetUID secrets vault, V8 FS monkey-patching, L7 DNS+HTTP allowlist proxy |
| `abulte/pi-sandbox` | macOS-focused | Keychain secrets, ephemeral container with persistent `pi/` dir |

### 4.10 Official Sandboxing Patterns (from pi-mono docs)

The project documents three patterns:

1. **Plain Docker** -- Full Pi process in a container with bind-mounted workspace. Simplest. API keys enter the container.
2. **Gondolin** -- MicroVM isolation for tools only; Pi process stays on the host, credentials stay on the host. Requires Node 23.6+ and QEMU.
3. **OpenShell** -- Managed orchestration with policy-controlled isolation and credential injection at the gateway level.

---

## 5. Platform-Specific Recommendations

### 5.1 macOS (Apple Silicon) -- The User's Primary Machine

This is the most constrained platform for strong sandboxing (no KVM, no native Linux namespaces), but it has excellent alternatives:

**Recommended stack (defense-in-depth with 3 boundaries):**

```
macOS host
  └── Boundary 1: Lima/Colima Linux VM (VZ.framework, resource limits via cgroups)
       └── Boundary 2: Podman rootless container (no daemon, user namespaces, capability dropping)
            └── Boundary 3: macOS Seatbelt sandbox-exec (.sb profile, filesystem+network allowlist)
                 └── Pi Agent process (node/npm)
```

**Why this stack:**

1. **Lima/Colima** provides a first-class Linux VM on Apple Silicon. It uses Apple's Virtualization.framework (fast, native), supports Rosetta 2 for x86 images (`--vz-rosetta`), and provides automatic virtiofs filesystem sharing with the macOS host. It is free, easy to install (`brew install colima && colima start --vm-type=vz`), and well-maintained.

2. **Podman rootless** runs inside the Colima VM. It has better security defaults than Docker (rootless-by-default, no daemon, automatic user namespaces, container escape success rate reportedly ~0.3% vs Docker's ~12%). It is Docker CLI-compatible (`alias docker=podman`).

3. **macOS Seatbelt (sandbox-exec)** is the native kernel-level MAC framework that powers App Store sandboxing. It is used in production by both Anthropic (Claude Code) and OpenAI (Codex CLI) for their AI agent tool execution. It allows writing explicit allowlist profiles: "Pi can read/write this project directory, can execute node/npm/git, can access localhost, and nothing else." It has negligible overhead (kernel-level, no daemon).

**Key limitations to be aware of:**
- `sandbox-exec` is technically deprecated since macOS Sierra, though still fully functional on Sequoia. Apple may remove it in a future release.
- APFS firmlinks cause path resolution edge cases (rules for `/Users/luke` may fail because the kernel resolves to `/System/Volumes/Data/Users/luke`).
- TCC (Transparency Consent Control) can override sandbox rules (e.g., a `file-read*` deny might be overridden if the user has granted Full Disk Access).
- No resource limits from Seatbelt alone -- the Colima VM provides cgroups for CPU/memory/disk limits.

**Concrete path:**

```bash
# 1. Install prerequisites
brew install colima podman

# 2. Start Colima with Apple Virtualization.framework
colima start --vm-type=vz --vz-rosetta --cpu 4 --memory 8 --disk 60

# 3. Pull/build the Pi container image (using Podman, which is Docker CLI-compatible)
podman build -t pi-sandbox -f - . <<'EOF'
FROM node:24-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates git ripgrep fd-find
RUN npm install -g --ignore-scripts @mariozechner/pi-coding-agent
RUN useradd -m -s /bin/bash pi && mkdir -p /workspace && chown pi:pi /workspace
USER pi
WORKDIR /workspace
ENTRYPOINT ["pi"]
EOF

# 4. Create a Seatbelt profile for Pi
cat > /tmp/pi-sandbox.sb <<'SCHEME'
(version 1)
(deny default)
(allow file-read* (subpath "/Users/<username>/projects"))  ; adjust to your project tree
(allow file-write* (subpath "/Users/<username>/projects"))
(allow file-read* (subpath "/opt/homebrew"))
(allow file-read* (subpath "/usr"))
(allow process-exec (literal "/opt/homebrew/bin/node"))
(allow process-exec (literal "/opt/homebrew/bin/npm"))
(allow process-fork)
(allow network* (local ip "localhost:*") (remote ip "localhost:*"))
(allow network* (remote ip "0.0.0.0/0:443"))
(deny network*)
SCHEME

# 5. Run Pi with layered isolation
podman run --rm -it \
  --name pi-agent \
  --cap-drop ALL \
  --no-new-privileges \
  --read-only --tmpfs /tmp:noexec \
  --memory 4g --cpus 2 --pids-limit 100 \
  --network slirp4netns \
  -v "$(pwd):/workspace:rw" \
  -v "pi-config:/home/pi/.pi:rw" \
  -v "$HOME/.gitconfig:/home/pi/.gitconfig:ro" \
  -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  -e TERM="$TERM" \
  pi-sandbox
```

**Simpler variant (skip Seatbelt for initial experimentation):**

The Colima VM + Podman rootless container alone provides reasonable isolation for the "tinker" goal. The Seatbelt layer can be added later when the user wants to understand kernel-level MAC on macOS. Start with just Colima + Podman, get Pi working inside the container, and then add the `.sb` profile as a learning exercise.

### 5.2 Windows x86_64 -- Secondary Machine (SSH Access)

This platform has stronger built-in isolation options:

**Recommended stack:**

```
Windows host
  └── Boundary 1: WSL2 Linux VM (Hyper-V backed, full kernel isolation)
       └── Boundary 2: Bubblewrap (bwrap) (Linux namespaces + seccomp, explicit bind mounts)
            └── Pi Agent process
```

**Why this stack:**

1. **WSL2** provides a real Linux kernel running in a lightweight Hyper-V VM. This is a true hardware VM boundary between the Linux environment and the Windows host. It is deeply integrated into Windows and well-supported.

2. **Bubblewrap** provides per-command namespace isolation inside WSL2. The model is perfect for Pi: create a new mount namespace with ONLY the project directory and system libraries visible, a new network namespace (loopback-only or allowlisted), and a new PID namespace. It is extremely lightweight (~2-5MB per sandbox, ~few ms startup) and auditable (~3K lines of C). Used in production by Flatpak.

**Concrete path:**

```bash
# Inside WSL2:

# 1. Install Node 24 and dependencies
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt-get install -y nodejs git ripgrep fd-find bubblewrap

# 2. Install Pi globally
npm install -g --ignore-scripts @mariozechner/pi-coding-agent

# 3. Run Pi with bubblewrap
bwrap \
  --ro-bind /usr /usr \
  --ro-bind /lib /lib \
  --ro-bind /lib64 /lib64 \
  --ro-bind /bin /bin \
  --ro-bind /etc /etc \
  --proc /proc \
  --dev /dev \
  --tmpfs /tmp \
  --bind "$(pwd)" /workspace \
  --bind "$HOME/.pi" "$HOME/.pi" \
  --ro-bind "$HOME/.gitconfig" "$HOME/.gitconfig" \
  --chdir /workspace \
  --unshare-net \
  --unshare-pid \
  --unshare-ipc \
  -- \
  pi -p "Your prompt here" --approve
```

The `--unshare-net` flag creates a loopback-only network namespace. For Pi's LLM API access, you would need to set up a veth pair + bridge with restricted outbound access (allowlisting only the LLM provider's API IP ranges). Alternatively, for initial experimentation, omit `--unshare-net` and instead use a domain allowlist at the WSL2 iptables level.

**Note on SSH access:** Since the Windows machine is accessed via SSH, headless/non-interactive Pi modes (`-p`, `--mode json`, `--mode rpc`) will be the practical interface. The interactive TUI requires a proper terminal, which is available over SSH if the client supports it, but headless operation is simpler for remote use.

---

## 6. Recommended Approach

### 6.1 Which Solution to Use and Why

**For macOS Apple Silicon (primary machine): Colima + Podman rootless container.**

This is the recommendation. Here is why:

1. **It works.** Colima's VZ.framework backend is native, fast, and well-tested on Apple Silicon. Podman runs seamlessly inside it. This is a supported, documented path used by thousands of macOS developers.

2. **It provides meaningful isolation.** The Colima VM creates a kernel boundary between Pi and macOS. If Pi's `bash` tool runs `rm -rf /`, it trashes the Linux VM, not the Mac. If a container escape occurs, the attacker lands in the disposable Linux VM. This is two boundaries (VM + container) deep.

3. **It is the right complexity level for "折腾".** The user wants to understand the technology. Colima + Podman is simple enough to set up in 15 minutes and understand, but layered enough to explore: virtiofs filesystem sharing, cgroups resource limits, container networking models, user namespace remapping.

4. **It maps to the existing community.** The Plain Docker pattern from pi-mono's official docs is directly portable to Podman. Nine community Docker images provide reference implementations. The user can start with a basic setup and progressively add hardening from the community's work.

5. **Filesystem sharing is clean.** virtiofs provides bidirectional filesystem access between macOS and the Linux VM, which is what Pi needs to edit project files that live on the host.

**macOS Seatbelt (sandbox-exec) is the "graduate school" layer.** It represents the next level of understanding -- how Apple's kernel MAC framework works, how to write Scheme-like sandbox profiles, the edge cases of firmlinks and TCC. I recommend exploring this after the Colima + Podman setup is working and understood.

**For Windows x86_64 (SSH machine): WSL2 + Bubblewrap.**

WSL2 provides the VM boundary. Bubblewrap provides per-command namespace isolation. This combination is lightweight, fast, and teaches the fundamentals of Linux namespaces and seccomp -- core sandboxing primitives.

### 6.2 Phased Implementation Plan

**Phase 1: Get Pi running in a basic container (1-2 hours)**
- Install Colima and Podman on macOS
- Build a minimal Pi container image (Node 24 + Pi + git + ripgrep)
- Mount the project directory and config volume
- Pass API key via environment variable
- Run Pi interactively inside the container
- **Goal:** Pi edits files on the host, container provides baseline isolation.

**Phase 2: Harden the container (1-2 hours)**
- Add `--cap-drop ALL`, `--no-new-privileges`
- Make rootfs read-only with `--tmpfs /tmp:noexec`
- Add resource limits (CPU, memory, PID count)
- Test what breaks and adjust
- **Goal:** Understand what capabilities Pi actually needs and what restrictions are feasible.

**Phase 3: Explore network isolation (1-2 hours)**
- Try `--network none` and observe what fails (LLM API calls, npm installs, git clone)
- Set up a domain allowlist approach (iptables/nftables inside the VM)
- Understand Pi's startup network calls and how to suppress them
- **Goal:** Pi can reach its LLM provider but nothing else.

**Phase 4: macOS Seatbelt (optional, 2-3 hours)**
- Write a `.sb` profile that allows Pi to read/write only the project directory
- Learn about path resolution, firmlinks, and TCC interactions
- Test with system directories that should be blocked (~/.ssh, ~/.aws, ~/Library)
- **Goal:** Kernel-level filesystem access control, defense-in-depth with three boundaries.

**Phase 5: Windows WSL2 + Bubblewrap (2-3 hours)**
- Set up WSL2 on the Windows machine
- Install Node, Pi, and Bubblewrap
- Build a bwrap launch script with explicit bind mounts
- Configure network allowlisting for the LLM provider
- **Goal:** Lightweight namespace-based sandbox on the secondary machine.

### 6.3 What CubeSandbox Would Have Given Us (And What We Lose)

To be clear about the tradeoff:

| What CubeSandbox Provides | What Our Recommended Stack Provides |
|---------------------------|-------------------------------------|
| Hardware-level isolation (dedicated guest kernel) | VM boundary + container namespace isolation |
| Sub-60ms sandbox creation from snapshots | Container startup (~200ms) or process startup (bwrap, ~few ms) |
| 2,000+ sandboxes per server | Single sandbox per Colima VM instance |
| E2B SDK compatibility (standardized API) | Docker/Podman CLI (well-understood but not agent-specific) |
| Production-proven at billions of invocations/day | Production-proven at individual developer scale |
| Credential injection at L7 proxy (sandbox never sees secrets) | API key as env var (enters the container) |
| L7 egress domain filtering | iptables/nftables IP-based filtering (less granular) |

The practical difference: CubeSandbox is a platform for **hosting** AI agents at scale. Our recommended stack is for **running** an AI agent locally for development. Both provide isolation, but at different scales and with different ergonomics. The local stack sacrifices multi-tenancy density and some security features (credential proxy injection) for simplicity and platform compatibility.

---

## 7. Open Questions / Next Steps

### 7.1 What We Still Don't Know

1. **Pi's actual syscall footprint.** Which Linux syscalls does Pi actually make? Seccomp profiles are written by trial and error unless we trace actual syscalls. Using `strace` (or `--security-opt seccomp=unconfined` in Docker/Podman) we can build a minimum-necessary syscall whitelist. Without this, seccomp hardening is brittle.

2. **Node.js-specific escape vectors.** Node.js has `child_process.exec`, `child_process.spawn`, and `vm.runInNewContext`. Does Pi's tool execution model use any of these in ways that could bypass namespace isolation? The `bash` tool is explicitly `child_process.exec`-based, which is captured by the container boundary, but extension code may have additional execution paths.

3. **OAuth flow in containers.** If the user wants to use Anthropic OAuth (rather than API key), the OAuth flow requires a browser and a local callback server on port 53692. Can this work through Colima's port forwarding? Does `podman run --network slirp4netns` support the port forwarding needed? This needs testing.

4. **Extension and skill installation at runtime.** Pi can install extensions and skills at runtime. These are TypeScript/Node.js code that execute in the Pi process. A malicious extension would have the same permissions as Pi inside the sandbox. Can extensions be limited to read-only installation paths? Does Pi support an extension approval workflow?

5. **Apple Silicon Node.js native modules.** Some npm packages include native (C++) addons compiled for specific architectures. Node 24 on Apple Silicon inside Colima's VM should handle this correctly (the VM is aarch64, Node in the container is aarch64), but community Docker images that target `node:24-bookworm-slim` (which is multi-arch) may pull x86_64 images if not careful about platform tags.

6. **Disk usage growth.** Pi's session files can grow large over time. The `~/.pi/agent/sessions/` directory needs monitoring or a cleanup policy for long-running containers.

7. **Seatbelt on macOS 15 Sequoia.** `sandbox-exec` works today, but Apple's deprecation timeline is unknown. We should investigate whether `AppSandbox` (the entitlement-based successor) can achieve the same per-process allowlisting from the command line, or whether `sandbox-exec` has a replacement that isn't yet widely known.

### 7.2 Suggested Next Steps

1. **Build the Phase 1 container and test Pi end-to-end.**
   - Can Pi edit files on the macOS host via virtiofs?
   - Does the TUI render correctly with `-e TERM=$TERM`?
   - Do all Pi tools (`read`, `write`, `edit`, `bash`, `grep`) work inside the container?

2. **Trace Pi's syscalls to build a minimal seccomp profile.**
   - Run `strace -f -c pi -p "hello"` inside the container to see syscall frequency and types.
   - Build a seccomp JSON profile that allows only the observed syscalls.
   - Test with Podman's `--security-opt seccomp=<profile>`.

3. **Test network isolation patterns.**
   - Try `--network none` and document exactly what breaks.
   - Set up a domain allowlist using `/etc/hosts` in the container with a custom `/etc/resolv.conf` pointing to a filtering DNS proxy.
   - Alternatively, use iptables inside the Colima VM to restrict outbound traffic from the container's virtual interface to specific IP ranges.

4. **Evaluate the Gondolin pattern on macOS.**
   - Gondolin runs Pi's tools in a QEMU microVM while Pi itself stays on the host. This keeps credentials on the host and limits the blast radius to the tool execution environment.
   - Is Gondolin supported on Apple Silicon? What is the QEMU guest image story?
   - This might be a better fit than the full-container approach if the goal is tool isolation rather than full process isolation.

5. **Explore Pi's `--mode rpc` for programmatic sandbox control.**
   - The RPC mode could allow a custom sandbox wrapper to intercept tool calls, validate arguments, and enforce policy before execution.
   - This is the approach that `gni/pi-coding-agent-container` takes with its V8 FS monkey-patching.
   - Could a lightweight supervisor process sit between the user and Pi, enforcing sandbox policy on each tool invocation?

6. **If Windows WSL2 is the target for a secondary setup, validate Bubblewrap on WSL2.**
   - Does WSL2's kernel support user namespaces (required for unprivileged `bwrap`)?
   - Test that `bwrap --unshare-net` works correctly in the WSL2 environment.
   - Measure performance overhead of bwrap under WSL2 vs native Linux.

---

## Appendix: Quick-Reference Command Cheat Sheet

### macOS: Colima + Podman Pi Sandbox

```bash
# Install
brew install colima podman

# Start VM
colima start --vm-type=vz --vz-rosetta --cpu 4 --memory 8

# Build Pi image
podman build -t pi-sandbox -f - . <<'EOF'
FROM node:24-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates git ripgrep fd-find
RUN npm install -g --ignore-scripts @mariozechner/pi-coding-agent
WORKDIR /workspace
ENTRYPOINT ["pi"]
EOF

# Run Pi
podman run --rm -it \
  --cap-drop ALL --no-new-privileges \
  --read-only --tmpfs /tmp:noexec \
  --memory 4g --cpus 2 --pids-limit 100 \
  -v "$(pwd):/workspace" \
  -v "pi-config:/root/.pi" \
  -v "$HOME/.gitconfig:/root/.gitconfig:ro" \
  -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  -e TERM="$TERM" \
  pi-sandbox
```

### Windows WSL2: Bubblewrap Pi Sandbox

```bash
# Install
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt-get install -y nodejs git ripgrep fd-find bubblewrap
npm install -g --ignore-scripts @mariozechner/pi-coding-agent

# Run Pi (loopback-only network, only project + system visible)
bwrap \
  --ro-bind /usr /usr --ro-bind /lib /lib --ro-bind /lib64 /lib64 \
  --ro-bind /bin /bin --ro-bind /etc /etc \
  --proc /proc --dev /dev --tmpfs /tmp \
  --bind "$(pwd)" /workspace --bind "$HOME/.pi" "$HOME/.pi" \
  --ro-bind "$HOME/.gitconfig" "$HOME/.gitconfig" \
  --chdir /workspace --unshare-net --unshare-pid --unshare-ipc \
  -- pi -p "Your task" --approve
```

### macOS Seatbelt Profile Skeleton

```scheme
(version 1)
(deny default)
;; Allow reading system paths Pi needs
(allow file-read* (subpath "/usr"))
(allow file-read* (subpath "/opt/homebrew"))
(allow file-read* (subpath "/Library"))
;; Allow read/write to the project directory ONLY
(allow file-read* (subpath "/Users/<username>/projects"))
(allow file-write* (subpath "/Users/<username>/projects"))
;; Allow Pi's config directory
(allow file-read* (subpath "/Users/<username>/.pi"))
(allow file-write* (subpath "/Users/<username>/.pi"))
;; Allow Node execution
(allow process-exec (literal "/opt/homebrew/bin/node"))
(allow process-fork)
;; Loopback-only network
(allow network* (local ip "localhost:*") (remote ip "localhost:*"))
(deny network*)
```
