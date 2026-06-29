# Sandbox Configuration

如何在一台 16GB RAM / 256GB SSD 的 macOS Apple Silicon 上，用外挂硬盘搭建 Pi coding agent 的隔离沙箱，主硬盘零占用。

## 为什么是这个方案

### CubeSandbox：服务器上极佳，本地不适用

[CubeSandbox](https://github.com/TencentCloud/CubeSandbox) 是腾讯云在 2026 年 4 月开源的 AI Agent 专用沙箱（Apache 2.0）。它不是研究原型——在开源之前已经在腾讯内部支撑了每天数十亿次调用，运行着腾讯的 AI 助手元宝。

**解决的问题：** Docker 容器共享宿主机内核，内核漏洞 = 宿主机沦陷。传统 VM 启动太慢（秒级）且太重。CubeSandbox 在这两者之间打出了一个新品类——**硬件级 KVM MicroVM 隔离 + 容器级性能**。

**核心数据：**

| 指标 | 数值 |
|------|------|
| 冷启动 | < 60ms（快照恢复，跳过 OS 引导） |
| 内存开销 | < 5MB / 实例（CoW 内存复用） |
| 密度 | 2000+ 沙箱 / 物理服务器 |
| 腾讯内部效果 | 迁移 AI 编码场景后，资源核时消耗降低 95.8% |
| 开源时间 | 2026-04-20 |
| 最新版本 | v0.4.0（2026-06-15），17 个 release |
| Star | ~6,600（不到 10 周） |

**怎么做到的：** 模板根文件系统从 OCI 镜像预构建 → 冷启动一次、初始化运行时 → 捕获内存快照 → 创建沙箱时用 XFS reflink 零拷贝克隆快照 → RustVMM 恢复，绕过整个 OS 启动序列。50 并发创建：平均 67ms，P95 90ms。

**架构（控制面 + 数据面）：**

| 组件 | 语言 | 职责 |
|------|------|------|
| CubeAPI | Rust (Axum) | E2B 兼容 REST API 网关 |
| CubeMaster | Go | 集群编排，创建/销毁/暂停/恢复 |
| Cubelet | Go | 每节点生命周期代理 |
| CubeShim | Rust | containerd Shim v2，容器抽象 → MicroVM 操作 |
| CubeHypervisor | Rust (RustVMM + KVM) | 轻量 VMM，Seccomp 加固 |
| CubeVS | eBPF (C) | 内核级虚拟交换机，无 iptables |
| CubeCoW | Rust | CoW 存储引擎，XFS reflink |
| CubeProxy | OpenResty | 反向代理路由请求到沙箱实例 |
| CubeEgress | OpenResty | L7 出口代理：域名过滤、凭证注入、审计 |

**六层隔离模型：**
1. **硬件隔离** — 每个沙箱跑独立 Linux 内核（KVM MicroVM），无共享内核逃逸面
2. **网络隔离** — CubeVS（eBPF）默认阻止所有私有/本地链路范围，沙箱无法触及宿主机网络命名空间
3. **出口控制** — CubeEgress L7 代理强制域名白名单，DNS 泄露或 TCP 握手完成前就阻断
4. **凭证保管** — API 密钥在出口代理层改写 HTTP 头注入，沙箱进程永远看不到真实密钥
5. **Seccomp 加固** — CubeHypervisor 跑在最小化系统调用白名单上
6. **可插拔认证** — CubeAPI 支持认证回调

**E2B SDK 兼容：** 现有 E2B 代码解释器沙箱的代码，改一个 URL 环境变量就能切到 CubeSandbox。

**部署：** 一条命令在线安装，支持 OpenCloudOS 9 / TencentOS 4 / Ubuntu 20.04+。需要 Linux x86_64 宿主机、KVM（或 PVM 内核）、XFS 文件系统、≥ 8GB RAM、≥ 50GB 磁盘。生产环境推荐 32 核 / 64GB。

**为什么在本地不适用：**
- 需要 KVM（`/dev/kvm`），macOS 不存在
- 所有二进制都是 x86_64，无 arm64 构建
- 需要 XFS reflink，macOS 不支持
- 嵌套虚拟化方案（macOS → Linux VM → CubeSandbox KVM MicroVM）性能极差且完全不受支持
- 32 核 / 64GB 的推荐配置望尘莫及

> **结论：** CubeSandbox 是服务器端多租户 AI Agent 沙箱的未来标准候选。如果你将来在 x86_64 Linux 服务器上部署 Pi 作为托管服务，CubeSandbox 是首选。但在 macOS 笔记本上搞本地开发，不适用。

### 选型：Colima + Docker

经过 12 种方案对比（Firecracker、Kata、gVisor、Podman、Bubblewrap 等），最终选 Colima + Docker：

**Colima** 是 macOS 上最好的容器方案：
- 使用 Apple 原生 Virtualization.framework（VZ），不是 QEMU 模拟，性能接近原生
- 支持 Rosetta 2 透传（x86 镜像也能跑）
- `brew install colima` 一条命令，比 Docker Desktop 轻得多
- VM 磁盘是稀疏文件，按需增长

**Docker（不是 Podman）** 的原因很实际：Colima 0.10.1 的 `--runtime podman` 直接报错不支持。Podman 和 Colima 是两个互斥的 VM 管理方案，不能嵌套。安全边界在 macOS ↔ Linux VM 这一层，VM 内部用 Docker 还是 Podman 差异不大——况且容器已经加了 cap-drop ALL 等加固。

### 安全模型：纵深防御

```
macOS 宿主机
  └── Colima Linux VM (VZ.framework)
       ├── 硬件 VM 边界（最外层）
       └── Docker 容器
            ├── --cap-drop ALL（剥离所有 Linux Capabilities）
            ├── --security-opt no-new-privileges（禁止 setuid 提权）
            ├── --memory 4g --cpus 2 --pids-limit 100（资源限制 + 防 fork bomb）
            └── Pi 进程
```

即使 Pi 越权，它也只能破坏 Linux VM 内部的环境，无法触达 macOS。

### 为什么去掉了 --read-only

最初加了 `--read-only --tmpfs /tmp:noexec`（根文件系统只读），但 Pi 需要在容器内执行各种操作（npm install 可能会写全局目录、某些工具需要写临时文件到非 /tmp 路径）。只读根文件系统阻碍了正常开发工作，所以去掉了。安全不依赖这一层。

### 容器退出即销毁

`docker run --rm` 确保容器退出后自动删除。只有两个东西会在退出后保留：
- `/workspace`（bind mount 到宿主机当前目录）
- `/home/pi/.pi`（pi-data 命名卷，存配置和会话）

## 存储：零占用主硬盘

主硬盘只有 256GB，外挂盘 715GB。所有持久存储走外挂盘：

```
/Volumes/Storage/colima/          ← Colima 家目录（VM 磁盘、配置）
~/.colima → /Volumes/Storage/colima/  ← 符号链接（主 SSD: 23 字节）
```

关键点：
- `~/.colima` 是符号链接，不是目录。Colima 读写时实际走外挂盘。
- VM 磁盘文件 `datadisk` 是 APFS 稀疏文件（声明 60GB，实际只占 ~3GB，随使用增长）。
- Docker 的所有镜像、层、卷都在 VM 磁盘里。
- `pi-data` 卷（Pi 的配置、会话、扩展）也在 VM 磁盘里。

验证命令：
```bash
ls -la ~/.colima                              # 确认是符号链接
du -sh ~/.colima                              # 主 SSD 用量（应为 0B）
ls -lh /Volumes/Storage/colima/_lima/_disks/colima/datadisk  # VM 磁盘位置
```

## 如何重建

Colima VM 停止或重启后，只需要：

```bash
colima start --vm-type=vz --vz-rosetta --cpu 4 --memory 6 --disk 60 --mount /Volumes/Storage/Project:w
```

Docker 镜像和卷不会丢失（都在外挂盘上）。

## 小巧思：在任何目录直接用 `pi`

这个沙箱有一个设计上的巧思 —— 你不需要「进到容器里」或者「切换到某个特定目录」才能用 Pi。你只需要在 macOS 宿主机上，`cd` 到任意一个工作目录，直接打 `pi`，那个目录就自动变成容器里的 `/workspace`。

原理：

```
你在宿主机哪个目录                      Pi 在容器里看到的就是
─────────────────                      ────────────────────
$ cd /Volumes/Storage/Project/my-app     Pi → /workspace (= my-app)
$ cd ~/Code/another-project              Pi → /workspace (= another-project)
$ cd /tmp/test                           Pi → /workspace (= /tmp/test)
```

怎么做到的：

1. `pi-sandbox.sh` 里有一行 `-v "$PWD:/workspace"`，把你在宿主机所在的当前目录 bind mount 进容器
2. `.zshrc` 里 alias `pi="/Volumes/Storage/Project/pi-study/pi-sandbox.sh"` 让你在任何地方都能敲 `pi`
3. Pi 在容器里从 `/workspace` 看出去，文件操作（read/write/edit/bash）都落在这个目录

所以 `pi` 这个 alias 本质上把 Docker 容器完全藏起来了 —— 你用起来就像它是一个本地命令，只是刚好跑在隔离环境里。

## 踩过的坑

1. **`credsStore: "desktop"`**：`~/.docker/config.json` 里这个配置指向不存在的 `docker-credential-desktop`，导致 `docker pull` 报错。改成空字符串解决。

2. **`--cap-drop ALL` 和 `--security-opt no-new-privileges` 不能用逗号分隔**：新版 Docker 的 `--cap-drop` 和 `--security-opt` 不能写在一起，必须分开。

3. **容器内的 `/home/pi` 没有写入权限**：`--read-only` 会影响 Pi 的 npm 操作，去掉后不影响安全边界（真正的隔离在 VM 层）。
