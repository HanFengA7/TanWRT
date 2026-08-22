#!/usr/bin/env bash
# OpenWRT 维护构建脚本（路线 A：官方 upstream + 个人分支 tanwrt-25.12）
# 用法：./build.sh
set -euo pipefail
cd "$(dirname "$0")"

echo "[1/5] 同步官方更新（rebase upstream/openwrt-25.12）"
git fetch upstream
git rebase upstream/openwrt-25.12 || {
  echo "rebase 冲突，请手动解决后执行：git rebase --continue && ./build.sh"
  exit 1
}

echo "[2/5] 更新并安装 feeds"
./scripts/feeds update -a
./scripts/feeds install -a

echo "[3/5] 应用配置差异 config.seed"
cp config.seed .config
make defconfig

echo "[4/5] 开始编译"
make -j"$(nproc)"

echo "[5/5] 推送更新到 origin (TanWRT)"
# rebase 会改写提交哈希，普通 push 会被拒，必须用 --force-with-lease
# 协作者在你 force-push 后需：git fetch && git reset --hard origin/tanwrt-25.12（或重新 clone）
git push --force-with-lease origin tanwrt-25.12

echo "构建完成，镜像位于 bin/targets/x86/64/"
