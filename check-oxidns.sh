#!/usr/bin/env bash
# check-oxidns.sh — 检查 package/luci-app-oxidns 是否需要更新到上游最新版
#
# 用法:
#   ./check-oxidns.sh            # 在 openwrt 仓库根目录运行
#   ./check-oxidns.sh -v         # 详细输出
#
# 逻辑:
#   1. 解析本地 package/luci-app-oxidns/Makefile 的 PKG_VERSION / PKG_RELEASE
#   2. 用 git ls-remote 拿上游仓库默认分支最新 commit (不依赖 GitHub API, 免限流)
#   3. 对比本地锁定的 upstream commit (写在 Makefile 注释 # UPSTREAM_COMMIT= 里)
#      若本地未记录 UPSTREAM_COMMIT, 仅报告上游最新 commit 供人工判断
set -euo pipefail

UPSTREAM_REPO="https://github.com/svenshi/luci-app-oxidns"
PKG_DIR="package/luci-app-oxidns"
VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

if [ ! -d "$PKG_DIR" ]; then
    echo "✗ 找不到 $PKG_DIR (请在 openwrt 仓库根目录运行)"
    exit 2
fi

# --- 1. 本地版本 ---
PKG_VERSION=$(grep -m1 '^PKG_VERSION' "$PKG_DIR/Makefile" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
PKG_RELEASE=$(grep -m1 '^PKG_RELEASE' "$PKG_DIR/Makefile" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
LOCAL_LOCKED=$(grep -m1 '# UPSTREAM_COMMIT=' "$PKG_DIR/Makefile" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || true)

echo "== 本地锁定版本 =="
echo "  PKG_VERSION : ${PKG_VERSION:-?}"
echo "  PKG_RELEASE : ${PKG_RELEASE:-?}"
if [ -n "$LOCAL_LOCKED" ]; then
    echo "  上游 commit : $LOCAL_LOCKED"
else
    echo "  上游 commit : (未记录, 建议首次同步后加一行 '# UPSTREAM_COMMIT=<sha>' 到 Makefile)"
fi

# --- 2. 上游最新 commit ---
echo ""
echo "== 上游最新 ($UPSTREAM_REPO) =="
if ! command -v git >/dev/null 2>&1; then
    echo "✗ 本机无 git, 无法 ls-remote"
    exit 3
fi

REMOTE_INFO=$(git ls-remote "$UPSTREAM_REPO" HEAD 2>/dev/null || true)
if [ -z "$REMOTE_INFO" ]; then
    echo "✗ 无法访问上游 (网络问题或仓库不存在)"
    exit 4
fi
UPSTREAM_COMMIT=$(echo "$REMOTE_INFO" | awk '{print $1}')
echo "  最新 commit : $UPSTREAM_COMMIT"

# 尝试拿最新 tag (best-effort, 失败不影响)
UPSTREAM_TAG=$(git ls-remote --tags "$UPSTREAM_REPO" 2>/dev/null | awk '{print $2}' | sed 's#refs/tags/##' | grep -v '\^{}$' | sort -V | tail -1 || true)
[ -n "$UPSTREAM_TAG" ] && echo "  最新 tag   : $UPSTREAM_TAG"

# --- 3. 对比 ---
echo ""
echo "== 结论 =="
if [ -z "$LOCAL_LOCKED" ]; then
    echo "△ 本地未记录上游 commit, 无法自动判断。当前上游最新为 $UPSTREAM_COMMIT"
    echo "  首次同步后请执行: 在 Makefile 顶部加 '# UPSTREAM_COMMIT=$UPSTREAM_COMMIT'"
elif [ "$LOCAL_LOCKED" = "$UPSTREAM_COMMIT" ]; then
    echo "✓ 已是最新 (本地锁定 = 上游最新)"
    exit 0
else
    echo "▲ 有更新可用!"
    echo "  本地锁定: $LOCAL_LOCKED"
    echo "  上游最新: $UPSTREAM_COMMIT"
    echo ""
    echo "  更新步骤:"
    echo "    rm -rf $PKG_DIR"
    echo "    git clone $UPSTREAM_REPO /tmp/luci-app-oxidns"
    echo "    cp -r /tmp/luci-app-oxidns $PKG_DIR"
    echo "    rm -rf $PKG_DIR/.git $PKG_DIR/README.md $PKG_DIR/AGENTS.md"
    echo "    # 在 $PKG_DIR/Makefile 顶部加: # UPSTREAM_COMMIT=$UPSTREAM_COMMIT"
    echo "    git add $PKG_DIR && git commit -m 'bump luci-app-oxidns to $UPSTREAM_COMMIT'"
    exit 1
fi
