#!/usr/bin/env bash
# OpenWRT 维护构建脚本（路线 A：官方 upstream + 个人分支 tanwrt-25.12）
# 用法：
#   ./build.sh          # 编 x86/64（默认，使用 config.seed）
#   ./build.sh r5c      # 编 NanoPi R5C（rockchip/armv8，使用 config-r5c.seed）
#   ./build.sh all      # 依次编 x86 + r5c（中间自动 make clean，耗时翻倍）
#   ./build.sh sync     # 仅检查并同步第三方包（有更新逐个交互确认）
#   ./build.sh --no-check  # 跳过第三方包更新检查
set -euo pipefail
cd "$(dirname "$0")"

SKIP_CHECK=0
for a in "$@"; do
  [ "$a" = "--no-check" ] && SKIP_CHECK=1
done

# ---- 第三方包清单（源码内嵌于 package/，不随 upstream 自动更新） ----
# 每项: 名称|本地目录|上游仓库|Makefile 相对路径|clone 后取用的子目录(空=仓库根)
#   openclash 仓库根含 luci-app-openclash/ 子目录，故 subdir=luci-app-openclash
declare -a PKG_NAMES=("oxidns" "openclash")
declare -A PKG_DIR PKG_REPO PKG_MK PKG_SUB
PKG_DIR[oxidns]="package/luci-app-oxidns"
PKG_REPO[oxidns]="https://github.com/svenshi/luci-app-oxidns"
PKG_MK[oxidns]="Makefile"
PKG_SUB[oxidns]=""

PKG_DIR[openclash]="package/openclash"
PKG_REPO[openclash]="https://github.com/vernesong/openclash"
PKG_MK[openclash]="luci-app-openclash/Makefile"
PKG_SUB[openclash]="luci-app-openclash"

# ---- 同步单个第三方包到上游最新版 ----
# 交互确认后 clone 覆盖、清残留、写 UPSTREAM_COMMIT 注释、git add（不自动 commit）。
sync_pkg() {
  local name="$1"
  local dir="${PKG_DIR[$name]}" repo="${PKG_REPO[$name]}" mk="${PKG_MK[$name]}" sub="${PKG_SUB[$name]}"
  [ -d "$dir" ] || { echo "✗ 找不到 $dir"; return 1; }

  local ver rel locked upstream
  ver=$(grep -m1 '^PKG_VERSION'  "$dir/$mk" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
  rel=$(grep -m1 '^PKG_RELEASE'  "$dir/$mk" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
  locked=$(grep -m1 '# UPSTREAM_COMMIT=' "$dir/$mk" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')

  upstream=$(git ls-remote "$repo" HEAD 2>/dev/null | awk '{print $1}') || true
  if [ -z "$upstream" ]; then
    echo "✗ 无法访问上游 ($repo)，请检查网络"
    return 1
  fi

  echo "本地版本: ${ver:-?}-r${rel:-?}  (锁定 commit: ${locked:-未记录})"
  echo "上游最新: $upstream"

  if [ -n "$locked" ] && [ "$locked" = "$upstream" ]; then
    echo "✓ 已是最新，无需同步"
    return 0
  fi

  if [ ! -t 0 ]; then
    echo "△ 非交互模式，跳过同步。如需更新请在终端前台运行: ./build.sh sync"
    return 0
  fi

  read -r -p "发现更新，是否同步 $name 到 $upstream? [y/N] " ans
  case "$ans" in
    y|Y)
      echo "正在同步 $name..."
      rm -rf "$dir"
      git clone "$repo" "/tmp/pkg-$name" >/dev/null 2>&1
      if [ -n "$sub" ]; then
        mkdir -p "$dir"
        cp -r "/tmp/pkg-$name/$sub/." "$dir/"
      else
        cp -r "/tmp/pkg-$name" "$dir"
      fi
      rm -rf "$dir/.git" "$dir/README.md" "$dir/AGENTS.md" "$dir/.github" "$dir/.gitattributes" "$dir/.gitignore"
      sed -i "1i # UPSTREAM_COMMIT=$upstream" "$dir/$mk"
      git add "$dir"
      echo "✓ 已同步 $name 到 $upstream（已 git add，尚未提交）"
      echo "  提交命令: git commit -m 'bump $name to $upstream'"
      ;;
    *)
      echo "已取消，未做任何改动"
      ;;
  esac
}

# ---- 第三方包更新检查（构建流程前置） ----
# 放在 rebase 之前：若同步了新版本，后续 defconfig/编译自然带上。
check_pkgs_update() {
  [ "$SKIP_CHECK" = 1 ] && return 0
  local name dir mk repo upstream ver rel locked
  for name in "${PKG_NAMES[@]}"; do
    dir="${PKG_DIR[$name]}"; mk="${PKG_MK[$name]}"; repo="${PKG_REPO[$name]}"
    [ -d "$dir" ] || continue
    ver=$(grep -m1 '^PKG_VERSION'  "$dir/$mk" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
    rel=$(grep -m1 '^PKG_RELEASE'  "$dir/$mk" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
    locked=$(grep -m1 '# UPSTREAM_COMMIT=' "$dir/$mk" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
    upstream=$(git ls-remote "$repo" HEAD 2>/dev/null | awk '{print $1}') || true
    if [ -z "$upstream" ]; then
      echo "  [$name] 无法访问上游，跳过检查（网络问题）"
      continue
    fi
    if [ -n "$locked" ] && [ "$locked" = "$upstream" ]; then
      echo "  [$name] 已是最新 ($ver-r$rel, 上游 $upstream)"
      continue
    fi
    echo "  [$name] 有更新可用！"
    echo "    本地锁定: ${locked:-未记录}"
    echo "    上游最新: $upstream"
    echo "    本地版本: ${ver:-?}-r${rel:-?}"
    if [ ! -t 0 ]; then
      echo "    （非交互模式，跳过自动同步；如需更新请手动运行 ./build.sh sync）"
      continue
    fi
    read -r -p "    是否同步 $name 到最新版? [y/N] " ans
    case "$ans" in
      y|Y) sync_pkg "$name" ;;
      *)   echo "    跳过 $name 更新（当前构建仍使用旧版本）" ;;
    esac
  done
}

TARGET="${1:-x86}"
case "$TARGET" in
  x86) SEED=config.seed ;;
  r5c) SEED=config-r5c.seed ;;
  all)
    "$0" ${SKIP_CHECK:+"--no-check"} x86
    "$0" ${SKIP_CHECK:+"--no-check"} r5c
    exit 0
    ;;
  sync)
    for name in "${PKG_NAMES[@]}"; do
      sync_pkg "$name"
    done
    exit 0
    ;;
  *) echo "未知目标: $TARGET（支持 x86 | r5c | all | sync）"; exit 1 ;;
esac

echo "[0/5] 检查第三方包更新"
check_pkgs_update

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
