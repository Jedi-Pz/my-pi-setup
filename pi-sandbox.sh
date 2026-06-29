#!/bin/bash
# pi-sandbox — 在隔离沙箱中运行 Pi 编码助手
#
# 用法：
#   ./pi-sandbox.sh                          # 交互模式
#   ./pi-sandbox.sh -p "你的提示词"            # 非交互
#   ./pi-sandbox.sh --model "claude-sonnet-4-6" -p "提示词"  # 换模型
#
# 配置：
#   卷 pi-data：Pi 的配置、会话、扩展、技能（持久化）
#   挂载 $PWD → /workspace（项目文件）

set -e

PI_DATA_VOLUME="pi-data"
PI_IMAGE="pi-sandbox"
WORKSPACE="${WORKSPACE:-$(pwd)}"

# 确保 .gitconfig 存在，避免 Docker 把它创建成目录
GITCONFIG=""
if [ -f "$HOME/.gitconfig" ]; then
    GITCONFIG="-v $HOME/.gitconfig:/home/pi/.gitconfig:ro"
fi

# 只在真实终端里才用 -it（管道/脚本里不加）
DOCKER_FLAGS=""
if [ -t 0 ]; then
    DOCKER_FLAGS="-it"
fi

exec docker run --rm $DOCKER_FLAGS \
  --cap-drop ALL \
  --security-opt no-new-privileges=true \
  --memory 4g --cpus 2 --pids-limit 100 \
  -v "$WORKSPACE:/workspace:rw" \
  -v "${PI_DATA_VOLUME}:/home/pi/.pi" \
  $GITCONFIG \
  -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-any}" \
  -e TERM="${TERM:-xterm-256color}" \
  "$PI_IMAGE" "$@"