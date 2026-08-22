# TanWRT 同步 OpenWRT 官方更新指南

本仓库采用「路线 A」轻量维护模式：以官方 OpenWRT 为基座，把自己的定制作为增量层叠在上面。
核心目标——**既能持续同步官方更新，又能保留自己的配置与改动，且升级到下一个大版本（如 26）时改动可整体重放**。

---

## 1. 仓库结构

| remote | 地址 | 作用 |
|---|---|---|
| `origin` | `git@github.com:HanFengA7/TanWRT.git` | 你自己的独立仓库（非 fork），对外协作、备份 |
| `upstream` | `https://github.com/openwrt/openwrt` | OpenWRT 官方仓库，只读，用于同步官方更新 |

| 分支 | 说明 |
|---|---|
| `tanwrt-25.12` | 你的工作分支，基于 `openwrt-25.12` + 你的定制（x86/64 + EFI + 4G 根分区；另支持 NanoPi R5C / rockchip，见 `config-r5c.seed`） |
| `openwrt-25.12` | 本地纯净跟踪官方的分支（建议平时不在此提交） |

初始化时的关键操作（已做过，留作备忘）：

```bash
git remote rename origin upstream            # 把官方改名 upstream
git remote add origin git@github.com:HanFengA7/TanWRT.git
git checkout -b tanwrt-25.12                 # 从官方提交切出工作分支
```

---

## 2. 日常同步官方更新（最省事）

直接在编译服务器 `/home/tc/op/openwrt` 执行一键脚本：

```bash
./build.sh
```

`build.sh` 会自动完成：

1. `git fetch upstream` — 拉取官方最新提交（不改动本地）
2. `git rebase upstream/openwrt-25.12` — 把官方新提交重放到你的分支之上
3. `./scripts/feeds update -a && install -a` — 同步官方包源（packages / luci / routing / telephony）
4. `cp config.seed .config && make defconfig` — 应用你的配置差异
5. `make -j$(nproc)` — 编译，镜像产出在 `bin/targets/x86/64/`
6. `git push --force-with-lease origin tanwrt-25.12` — 把更新推回你的仓库

---

## 3. 手动同步（想看清每一步时）

```bash
git fetch upstream                                       # 只下载，安全

git rebase upstream/openwrt-25.12                       # 官方新提交重放到 tanwrt-25.12 之上
# 若出现冲突：编辑冲突文件 → git add <文件> → git rebase --continue
# 放弃重放：git rebase --abort

./scripts/feeds update -a
./scripts/feeds install -a

cp config.seed .config
make defconfig
make -j$(nproc)

# rebase 改写了提交哈希，必须 force-with-lease（普通 push 会被拒）
git push --force-with-lease origin tanwrt-25.12
```

### 为什么用 rebase 而不是 merge

rebase 让你的提交始终「骑」在官方最新提交之上，历史是线性的，冲突只会出现在你改过的文件上，且后续查看 `git log` 清晰。
代价是 rebase 会**改写提交哈希**——这正是必须用 `--force-with-lease` 推送、且协作者需重置本地的原因。

---

## 4. 冲突解决

rebase 中途遇到冲突：

```bash
# 1. 看哪个文件冲突
git status

# 2. 手动编辑冲突文件（搜索 <<<<<<< 标记）

# 3. 标记已解决
git add <冲突文件>

# 4. 继续重放
git rebase --continue

# 5. 全部解决后重新跑构建
./build.sh
```

冲突面通常很小，因为你的定制只有 `config.seed`、`files/`、`build.sh` 和少量自有改动。

---

## 5. 升大版本（如 26）——不走 rebase

OpenWRT 每个大版本是**独立分支**（`openwrt-25.12`、`openwrt-26.x`），彼此不合并。
所以「升 26」不是把 `tanwrt-25.12` 直接 rebase 到 26（历史不连续，冲突会爆炸），而是**换基座 + 重放增量**：

```bash
git fetch upstream
git checkout -b tanwrt-26.x upstream/openwrt-26.x      # 新基座

# 重放你的增量层（这些资产跨版本复用）：
cp config.seed .config && make defconfig               # 配置差异（大版本间包符号会变，defconfig 会丢无效项，需核对）
cp -r files/ .                                          # 默认配置覆盖

# 把 feeds.conf 官方包源切到 26 分支：
#   src-git packages https://github.com/openwrt/packages;openwrt-26.x
#   src-git luci     https://github.com/openwrt/luci;openwrt-26.x
#   src-git myfeed   https://github.com/你/你的包           # 你自己的 feed 不变

./scripts/feeds update -a && ./scripts/feeds install -a
make -j$(nproc)                                          # 解决 26 引入的适配（内核升级、包 API 变动等）
git push -u origin tanwrt-26.x
```

**让「升版本」变轻松的精髓**：把定制都做成可移植资产，与源码解耦——

- 配置 → `config.seed` / `config-r5c.seed`（纯文本差异，不依赖整份 `.config`）
- 默认配置 → `files/` 目录（跨版本原样拷贝）
- 自己的包 → 独立 feed 仓（升版本只改 `feeds.conf` 指针）
- 补丁 → quilt/series 管理，便于重放

做到这几点，「升 26」几乎就是：换基座分支 + 把上面四样丢回去，几分钟搞定。

---

## 6. 协作者如何使用

```bash
git clone git@github.com:HanFengA7/TanWRT.git
cd TanWRT
git checkout tanwrt-25.12
./build.sh
```

**同步官方是维护者（你）的职责**——协作者没有 `upstream` remote，也不该直接跟官方，只用你推好的 `tanwrt-25.12` 即可。

⚠️ 维护者 force-push 后，协作者若已有本地副本，需重置：
```bash
git fetch
git reset --hard origin/tanwrt-25.12      # 或干脆重新 clone
```

---

## 7. 当前定制清单（tanwrt-25.12）

| 项 | 值 | 说明 |
|---|---|---|
| 目标 | `x86/64` Generic | 64 位 x86 通用（PC / 虚拟机） |
| 镜像 | EFI + BIOS | `GRUB_EFI_IMAGES=y`、`GRUB_IMAGES=y` |
| 包管理 | APK | `CONFIG_USE_APK=y`（opkg 已禁用，产出 `.apk`） |
| 根分区 | 4G（4096 MiB） | `CONFIG_TARGET_ROOTFS_PARTSIZE=4096`；镜像只含 16M 内核 + 4G squashfs 只读根，刷到 128G 盘后 OpenWRT 首次启动自动建 loop 覆盖层(rootfs_data)占满剩余≈124G |
| 内核 | 6.12 | x86 目标在 25.12 锁定，不可在 menuconfig 选 |
| 自带软件 | luci 等 | 见 `config*.seed` |

---

## 8. 注意事项

1. **`build.sh` 第 3 步 `cp config.seed .config` 会覆盖当前 `.config`**：
   临时改 `.config` 没存进 `config.seed` 会丢。要改配置就先改 `config.seed` 再 `make defconfig` 和提交。

2. **放大根分区重编会写大临时文件**：
   `gen_image_generic.sh` 用 `dd` 写零（非稀疏），会真实占满 `build_dir` 下约 `PARTSIZE × 2`（combined + efi 各一份）的空间。
   重编前务必 `df -h /` 确认空闲 > 该值，否则编译中途磁盘满会失败并残留巨文件（曾因此写满 140G 系统盘）。
   另外 `gen_image_generic.sh` 的 `dd bs=$(PARTSIZE)MiB conv=sync` 还需 PARTSIZE 大小的**连续内存**作缓冲：构建机仅 7.7G 内存，PARTSIZE 超过 ~4G 会 `dd: memory exhausted`，故 `ROOTFS_PARTSIZE` 不要设太大（当前 4096）。

3. **旧小写 fork `tanwrt` 已删除**（2026-08-22）：
   现仅保留独立仓库 `TanWRT`，无混淆。

4. **feeds 官方源已锁分支**：
   `feeds.conf.default` 中官方源已带 `;openwrt-25.12` 后缀，不会漂移到 `main`。

## 9. 多目标构建（x86 / NanoPi R5C）

本仓库同时维护两个设备，分属不同架构（x86/64 与 rockchip/armv8），OpenWRT 一份 `.config` 只能编一个，因此：

- `config.seed`：x86/64 Generic（EFI+BIOS）
- `config-r5c.seed`：NanoPi R5C（FriendlyElec，RK3568，双 2.5GbE，RTL8125 驱动自动默认选中）

`build.sh` 已参数化：

```bash
./build.sh          # 编 x86/64（默认，用 config.seed）
./build.sh r5c      # 编 NanoPi R5C（用 config-r5c.seed）
./build.sh all      # 依次编 x86 + R5C（中间自动 make clean，耗时翻倍）
```

切换架构时，`build.sh` 依据本地标记 `.built-target` 自动 `make clean` 清掉上次其他架构的产物，避免交叉污染；同架构连续构建则增量复用。两个镜像分别产出在 `bin/targets/x86/64/` 与 `bin/targets/rockchip/armv8/`。

新增设备时：复制一份 `config-<名>.seed`（基于对应 target + DEVICE，跑 `make defconfig && ./scripts/diffconfig.sh > config-<名>.seed`），再在 `build.sh` 的 `case` 里加一行即可。

---

## 10. 第三方包更新检查（内嵌于 package/）

以下第三方包以**源码内嵌**方式放在 `package/` 下，不通过 feeds 引入（OpenWRT 25.12 的 feeds 扫描无法正确展开外部 luci-app 包的 `luci.mk`，详见 [doc/CUSTOM_PACKAGES.md](CUSTOM_PACKAGES.md)）。因此它们**不会自动跟随上游**，需手动同步：

| 包 | 本地目录 | 上游仓库 | Makefile 路径 |
|---|---|---|---|
| `luci-app-oxidns` | `package/luci-app-oxidns` | `svenshi/luci-app-oxidns` | `Makefile` |
| `luci-app-openclash` | `package/openclash` | `vernesong/openclash` | `luci-app-openclash/Makefile` |

> OpenClash 仓库根只是容器，真正主包在 `luci-app-openclash/` 子目录；clone 后只取该子目录作为包内容（见 `PKG_SUB` 配置）。

### 版本锁定记录

各包锁定的上游 commit 写在对应 `Makefile` 顶部注释，例如：

```makefile
# UPSTREAM_COMMIT=c3a33c1d3407956fdf8f0e0b7c1a4c52e6ad9593
```

同步后该注释会自动更新为新的上游 commit，下次检查据此判断「已是最新」。

### 自动检查（构建前置）

`build.sh` 在 `[1/5] rebase` 之前插入了 `[0/5] 检查第三方包更新`，遍历 `PKG_NAMES` 清单：

- 解析本地版本 + `# UPSTREAM_COMMIT=` 注释，用 `git ls-remote` 拿上游最新 commit（不依赖 GitHub API，免限流）
- 已是最新 → 静默打印一行，继续构建
- 有更新 → 终端前台逐个交互询问是否同步；选 `y` 则自动 clone 覆盖并 `git add`，本次构建直接编进新版
- 非交互（后台/管道）→ 不卡住，仅提示手动运行 `./build.sh sync`

### 仅同步（不构建）

只想更新包、不想跑完整构建时：

```bash
./build.sh sync
```

行为：遍历所有第三方包 → 有更新则逐个交互确认（`发现更新，是否同步 <包名> 到 <commit>? [y/N]`）→ 选 `y` 后 clone 覆盖、清掉 `.git`/README、更新 `# UPSTREAM_COMMIT=` 注释、`git add`（**不自动 commit**，交给你写提交信息）。已是最新则直接退出。

### 跳过检查

```bash
./build.sh --no-check        # 跳过第三方包更新检查，直接构建
```

### 新增第三方包

在 `build.sh` 顶部往 `PKG_NAMES` 数组加一项，并补 `PKG_DIR` / `PKG_REPO` / `PKG_MK` / `PKG_SUB` 四个关联数组的对应条目即可，检查与同步逻辑自动覆盖。

### 手动同步步骤（以 openclash 为例，不依赖脚本时）

```bash
rm -rf package/openclash
git clone https://github.com/vernesong/openclash /tmp/openclash
mkdir -p package/openclash
cp -r /tmp/openclash/luci-app-openclash/. package/openclash/
rm -rf package/openclash/.git package/openclash/README.md
# 在 package/openclash/luci-app-openclash/Makefile 顶部加：# UPSTREAM_COMMIT=<上游最新 commit>
git add package/openclash
git commit -m "bump luci-app-openclash to <commit>"
```

