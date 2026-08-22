#!/usr/bin/env bash
# OpenWRT 维护构建脚本（路线 A：官方 upstream + 个人分支 my-25.12）
# 用法：./build.sh
set -euo pipefail
cd "$(dirname "$0")"

echo "[1/4] 同步官方更新（rebase upstream/openwrt-25.12）"
git fetch upstream
git rebase upstream/openwrt-25.12 || {
  echo "rebase 冲突，请手动解决后执行：git rebase --continue && ./build.sh"
  exit 1
}

echo "[2/4] 更新并安装 feeds"
./scripts/feeds update -a
./scripts/feeds install -a

echo "[3/4] 应用配置差异 config.seed"
cp config.seed .config
make defconfig

echo "[4/4] 开始编译"
make -j"$(nproc)"

echo "构建完成，镜像位于 bin/targets/x86/64/"
