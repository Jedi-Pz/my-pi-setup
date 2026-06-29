# CLAUDE.md

本仓库是一个可移植的 Pi 编码助手沙箱配置，基于 Colima + Docker，所有存储在外挂硬盘，主 SSD 零占用。

## 核心规则

- **所有文档、注释、描述必须用中文。** 代码（bash、Dockerfile 指令、JSON 键名）可以用英文。
- **不要主动提交或推送。** 除非明确要求，否则不执行 `git add`、`git commit`、`git push`。
- **不要写死个人路径。** 家目录用 `"~"`（YAML 里加引号防止被当 null），不要写 `/Users/xxx`。

## 架构

```
macOS 宿主机 (Apple Silicon, 16GB RAM, 256GB SSD)
  │
  │  ~/.colima → /Volumes/Storage/colima/  (符号链接)
  │
  └── Colima Linux 虚拟机 (VZ.framework, 4 核, 6GB 内存, 60GB 稀疏磁盘)
       │  VM 磁盘: /Volumes/Storage/colima/_lima/_disks/colima/datadisk
       │
       └── Docker 容器 (cap-drop ALL, no-new-privileges, 4GB 内存, 2 核, pid-limit 100)
            │  镜像: node:24-bookworm-slim + @earendil-works/pi-coding-agent
            │  非 root 用户: pi
            │
            └── Pi 编码助手
                 │  卷 pi-data: 配置、会话、扩展（持久化）
                 │  挂载 $PWD → /workspace（项目文件）
```

## 存储

- **所有持久存储在外挂硬盘 `/Volumes/Storage/`（715GB APFS）。**
- `~/.colima` 是符号链接，指向 `/Volumes/Storage/colima/`。
- Colima VM 磁盘文件 `datadisk` 是 APFS 稀疏文件（声明 60GB，实际按需增长）。
- Docker 镜像、层、卷全部在 VM 磁盘内。
- 主 SSD 持久占用：0 字节（仅符号链接本身）。
- 项目路径：`/Volumes/Storage/Project/pi-study/`

## 模型配置

- 本地代理：`cc-switch`（DeepSeek），监听 `127.0.0.1:15721`
- 完整实现 Anthropic Messages API，无需 compat 限制
- 容器内通过 `host.docker.internal:15721` 访问
- API key 任意值（代理不验证），真实密钥由代理持有
- Pi 的 `models.json` 只需一行 `baseUrl`
- 默认模型：`claude-opus-4-8`，思考级别：`xhigh`
- 切换后端只需改 cc-switch，Pi 这边零改动

## 仓库结构

- `Dockerfile` — Pi 容器镜像（Node 24 + pi 0.80.2 + git + ripgrep + fd）
- `pi-sandbox.sh` — 启动脚本
- `cookbook/` — 按编号排序的实战笔记（01、02、03…），README.md 是目录
- `docs/superpowers/` — gitignored，不在仓库里

## 常用操作

```bash
# 构建/升级镜像
docker build --no-cache -t pi-sandbox .

# 使用 Pi
./pi-sandbox.sh                          # 交互模式
./pi-sandbox.sh --continue               # 接着上次对话
./pi-sandbox.sh -p "提示词" --no-session  # 一次性

# Colima 管理
colima start   # 启动（配置在 /Volumes/Storage/colima/default/colima.yaml）
colima stop    # 停止
colima status  # 查看状态

# 确认存储正确
ls -la ~/.colima                                    # 应该是符号链接
du -sh ~/.colima                                    # 主 SSD 用量（应为 0B）
ls -lh /Volumes/Storage/colima/_lima/_disks/colima/datadisk  # VM 磁盘
```

## 注意

- `colima.yaml` 不在仓库里，在 `/Volumes/Storage/colima/default/colima.yaml`。显式指定 mounts 会覆盖默认 `$HOME` 挂载，需要同时写 `"~"` 和外挂盘路径。
- YAML 里 `~` 不加引号会被解析成 null，写成 `location: "~"`。
- Colima 0.10.1 不支持 `--runtime podman`，只有 docker 和 containerd。
- Pi 的配置和数据在 `pi-data` Docker 卷里（`models.json`、`settings.json`、`auth.json`、`sessions/`），不会被 `docker build` 覆盖。
- 仓库是公开的（Jedi-Pz/my-pi-setup），不要提交任何凭据或敏感信息。
