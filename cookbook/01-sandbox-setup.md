# Sandbox Configuration

如何在一台 16GB RAM / 256GB SSD 的 macOS Apple Silicon 上，用外挂硬盘搭建 Pi coding agent 的隔离沙箱，主硬盘零占用。

## 为什么是这个方案

### CubeSandbox：理论最强，实际不行

最初想用腾讯云的 CubeSandbox——硬件级 KVM MicroVM 隔离，60ms 冷启动，2000+ 沙箱/服务器。但它的硬性要求全部不满足：
- 需要 Linux x86_64 宿主机 + KVM（macOS 没有）
- 需要 XFS 文件系统（macOS 不支持）
- 所有二进制都是 x86_64（Apple Silicon 跑不了）
- 嵌套虚拟化方案在 macOS 上不可行且性能极差

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

## 踩过的坑

1. **`credsStore: "desktop"`**：`~/.docker/config.json` 里这个配置指向不存在的 `docker-credential-desktop`，导致 `docker pull` 报错。改成空字符串解决。

2. **`--cap-drop ALL` 和 `--security-opt no-new-privileges` 不能用逗号分隔**：新版 Docker 的 `--cap-drop` 和 `--security-opt` 不能写在一起，必须分开。

3. **容器内的 `/home/pi` 没有写入权限**：`--read-only` 会影响 Pi 的 npm 操作，去掉后不影响安全边界（真正的隔离在 VM 层）。
