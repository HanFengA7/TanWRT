#!/usr/bin/env bash
# OpenWRT 维护构建脚本（路线 A：官方 upstream + 个人分支 tanwrt-25.12）
# 用法：
#   ./build.sh          # 编 x86/64（默认，使用 config.seed）
#   ./build.sh r5c      # 编 NanoPi R5C（rockchip/armv8，使用 config-r5c.seed）
#   ./build.sh all      # 依次编 x86 + r5c（中间自动 make clean，耗时翻倍）
set -euo pipefail
cd "$(dirname "$0")"

TARGET="${1:-x86}"

case "$TARGET" in
  x86) SEED=config.seed ;;
  r5c) SEED=config-r5c.seed ;;
  all)
    "$0" x86
    "$0" r5c
    exit 0
    ;;
  *) echo "未知目标: $TARGET（支持 x86 | r5c | all）"; exit 1 ;;
esac

echo "[1/5] 同步官方更新（rebase upstream/openwrt-25.12）"
git fetch upstream
git rebase upstream/openwrt-25.12 || {
  echo "rebase 冲突，请手动解决后执行：git rebase --continue && ./build.sh $TARGET"
  exit 1
}

echo "[2/5] 更新并安装 feeds"
./scripts/feeds update -a
./scripts/feeds install -a

echo "[3/5] 应用配置差异 $SEED"
cp "$SEED" .config
make defconfig

# 切换架构时清掉上一次其他架构的产物，避免交叉污染；同架构则增量复用
MARKER=.built-target
if [ -f "$MARKER" ] && [ "$(cat "$MARKER" 2>/dev/null)" != "$TARGET" ]; then
  echo "[4/5] 检测到目标切换（$TARGET），清理上次其他架构产物"
  make clean
fi

echo "[4/5] 开始编译 ($TARGET)"
make -j"$(nproc)"

echo "$TARGET" > "$MARKER"

echo "[5/5] 推送更新到 origin (TanWRT)"
# rebase 会改写提交哈希，普通 push 会被拒，必须用 --force-with-lease
# 协作者在你 force-push 后需：git fetch && git reset --hard origin/tanwrt-25.12（或重新 clone）
git push --force-with-lease origin tanwrt-25.12

echo "构建完成，镜像位于 bin/targets/（x86: x86/64/，R5C: rockchip/armv8/）"
