#!/usr/bin/env bash
# OpenWRT 维护构建脚本（路线 A：官方 upstream + 个人分支 tanwrt-25.12）
# 用法：
#   ./build.sh          # 编 x86/64（默认，使用 config.seed）
#   ./build.sh r5c      # 编 NanoPi R5C（rockchip/armv8，使用 config-r5c.seed）
#   ./build.sh all      # 依次编 x86 + r5c（中间自动 make clean，耗时翻倍）
#   ./build.sh --no-check  # 跳过 oxidns 更新检查
set -euo pipefail
cd "$(dirname "$0")"

OXIDNS_REPO="https://github.com/svenshi/luci-app-oxidns"
OXIDNS_DIR="package/luci-app-oxidns"
SKIP_CHECK=0
for a in "$@"; do
  [ "$a" = "--no-check" ] && SKIP_CHECK=1
done

TARGET="${1:-x86}"
case "$TARGET" in
  x86) SEED=config.seed ;;
  r5c) SEED=config-r5c.seed ;;
  all)
    "$0" ${SKIP_CHECK:+"--no-check"} x86
    "$0" ${SKIP_CHECK:+"--no-check"} r5c
    exit 0
    ;;
  *) echo "未知目标: $TARGET（支持 x86 | r5c | all）"; exit 1 ;;
esac

# ---- oxidns 第三方包更新检查 ----
# 放在 rebase 之前：若同步了新版本，后续 defconfig/编译自然带上。
check_oxidns_update() {
  [ "$SKIP_CHECK" = 1 ] && return 0
  [ -d "$OXIDNS_DIR" ] || return 0

  local ver rel locked upstream
  ver=$(grep -m1 '^PKG_VERSION'  "$OXIDNS_DIR/Makefile" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
  rel=$(grep -m1 '^PKG_RELEASE'  "$OXIDNS_DIR/Makefile" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
  locked=$(grep -m1 '# UPSTREAM_COMMIT=' "$OXIDNS_DIR/Makefile" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')

  # 拿上游最新 commit（不依赖 GitHub API，免限流）
  upstream=$(git ls-remote "$OXIDNS_REPO" HEAD 2>/dev/null | awk '{print $1}') || true
  if [ -z "$upstream" ]; then
    echo "  [oxidns] 无法访问上游，跳过检查（网络问题）"
    return 0
  fi

  if [ -n "$locked" ] && [ "$locked" = "$upstream" ]; then
    echo "  [oxidns] 已是最新 ($ver-r$rel, 上游 $upstream)"
    return 0
  fi

  echo "  [oxidns] 有更新可用！"
  echo "    本地锁定: ${locked:-未记录}"
  echo "    上游最新: $upstream"
  echo "    本地版本: ${ver:-?}-r${rel:-?}"

  # 仅在 TTY 下交互询问；非交互（后台/管道）自动跳过
  if [ ! -t 0 ]; then
    echo "    （非交互模式，跳过自动同步；如需更新请手动运行 check-oxidns.sh）"
    return 0
  fi

  read -r -p "    是否同步 luci-app-oxidns 到最新版? [y/N] " ans
  case "$ans" in
    y|Y)
      echo "    正在同步..."
      rm -rf "$OXIDNS_DIR"
      git clone "$OXIDNS_REPO" /tmp/luci-app-oxidns >/dev/null 2>&1
      cp -r /tmp/luci-app-oxidns "$OXIDNS_DIR"
      rm -rf "$OXIDNS_DIR/.git" "$OXIDNS_DIR/README.md" "$OXIDNS_DIR/AGENTS.md"
      # 写入上游 commit 注释，供下次检查对比
      sed -i "1i # UPSTREAM_COMMIT=$upstream" "$OXIDNS_DIR/Makefile"
      git add "$OXIDNS_DIR"
      echo "    已同步到 $upstream（已 git add，将在构建后一起提交）"
      ;;
    *)
      echo "    跳过 oxidns 更新（当前构建仍使用旧版本）"
      ;;
  esac
}

echo "[0/5] 检查 luci-app-oxidns 更新"
check_oxidns_update

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
