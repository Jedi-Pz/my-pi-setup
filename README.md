# 我的 Pi 配置

在 macOS (Apple Silicon) 上通过 Colima 虚拟机 + Docker 容器运行 Pi 编码助手的沙箱。

## 特性

- **在哪用就在哪工作** — 你 `cd` 到哪个目录，敲 `pi`，那个目录就是容器里的工作区。换项目不需要切配置，Docker 容器完全透明
- **存储路径可指定** — 把 `~/.colima` 符号链接到任意位置（外挂盘、内建 SSD、甚至 NAS），Colima VM 和全部容器数据就落在哪。不写死路径、不强制外挂
- **容器安全隔离** — cap-drop ALL、no-new-privileges、4GB 内存限制、2 核 CPU、pid-limit 100
- **会话持久化** — `pi --continue` 接着聊、`pi --resume` 选历史对话
- **可移植** — 不写死路径，`colima.yaml` 用 `"~"` 自动解析家目录，clone 下来改几个地方就能用
- **一条命令升级** — `docker build --no-cache -t pi-sandbox .`，配置和会话不受影响

## 快速开始

```bash
# 1. 安装依赖
brew install colima docker

# 2. 启动 Colima（按你的路径调整挂载）
colima start --vm-type=vz --vz-rosetta --cpu 4 --memory 6 --disk 60

# 3. 确保 colima.yaml 里有这些挂载（没有就加上）：
#    mounts:
#      - location: "<你的项目盘>"  # 你放项目的地方
#        writable: true
#      - location: "~"
#        writable: true

# 4. 构建 Pi 容器镜像
docker build -t pi-sandbox .

# 5. 在 ~/.zshrc 里加 alias
#    alias pi="<本仓库路径>/pi-sandbox.sh"

# 使用
pi                          # 交互模式
pi --continue               # 接着上次对话继续
pi -p "..." --no-session    # 一次性，不保存会话
```

## 文件说明

- `Dockerfile` — Pi 容器镜像（Node 24 + pi 0.80.2 + git + ripgrep + fd）
- `pi-sandbox.sh` — 启动脚本（cap-drop ALL、资源限制、持久化卷）
- `cookbook/` — 配置指南与踩坑笔记

## 架构

```
macOS 宿主机 → Colima Linux 虚拟机（VZ.framework）
  → Docker 容器（cap-drop ALL、4GB 内存、2 核 CPU）
    → Pi 编码助手
```

通过 `~/.colima` 符号链接控制存储位置，默认 Colima 会把 VM 磁盘和容器数据放在那里。

## 模型配置

`models.json` 把 Anthropic 指向本地代理（`cc-switch` 监听在 `host.docker.internal:15721`），和宿主机 Claude Code 用同一个模型（claude-opus-4-8）。

## 升级

```bash
docker build --no-cache -t pi-sandbox .
```