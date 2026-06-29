# Pi 编码助手沙箱
# ================
#
# 构建一个带安全加固的 Pi 容器镜像。
# 镜像本身是可移植的——不写死任何个人路径或凭据。
#
# 你需要为自己的机器做以下配置：
#
#   1. colima.yaml 挂载
#      Pi 通过 virtiofs 访问宿主机目录。把你希望 Pi 工作的路径加进去：
#        mounts:
#          - location: "<你的项目盘>"  # 如 /Volumes/Data
#            writable: true
#          - location: "~"             # 家目录（引号不能省！YAML 会把裸 ~ 当 null）
#            writable: true
#
#   2. pi-sandbox.sh
#      启动脚本会把 $PWD → /workspace（你在哪个目录执行 `pi`，
#      那个目录就成了容器的工作目录）。如果想固定项目路径，运行前
#      设一下 WORKSPACE 环境变量即可。
#
#   3. models.json（存在 pi-data Docker 卷里）
#      把 Anthropic 指向你的本地代理。详见 cookbook/02-model-config.md。
#
# 构建：docker build -t pi-sandbox .
# 运行：./pi-sandbox.sh           （或：alias pi="路径/pi-sandbox.sh"）

FROM node:24-bookworm-slim

# 系统依赖：git 版本控制、ripgrep + fd 文件搜索
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates git ripgrep fd-find \
    && rm -rf /var/lib/apt/lists/*

# Pi 编码助手（兼容 Anthropic API，通过本地代理连接）
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# 非 root 用户。/workspace 是宿主机目录的 bind-mount 目标。
RUN useradd -m -s /bin/bash pi \
    && mkdir -p /workspace \
    && chown pi:pi /workspace

USER pi
WORKDIR /workspace
ENTRYPOINT ["pi"]