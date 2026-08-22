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
| `tanwrt-25.12` | 你的工作分支，基于 `openwrt-25.12` + 你的定制（x86/64 + EFI + 16G 根分区） |
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

- 配置 → `config.seed`（纯文本差异，不依赖整份 `.config`）
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
| 根分区 | 16G（16384 MiB） | `CONFIG_TARGET_ROOTFS_PARTSIZE=16384`；128GB 盘剩约 112GiB 未分配 |
| 内核 | 6.12 | x86 目标在 25.12 锁定，不可在 menuconfig 选 |
| 自带软件 | luci 等 | 见 `config.seed` |

---

## 8. 注意事项

1. **`build.sh` 第 3 步 `cp config.seed .config` 会覆盖当前 `.config`**：
   临时改 `.config` 没存进 `config.seed` 会丢。要改配置就先改 `config.seed` 再 `make defconfig` 和提交。

2. **放大根分区重编会写大临时文件**：
   `gen_image_generic.sh` 用 `dd` 写零（非稀疏），会真实占满 `build_dir` 下约 `PARTSIZE × 2`（combined + efi 各一份）的空间。
   重编前务必 `df -h /` 确认空闲 > 该值，否则编译中途磁盘满会失败并残留巨文件（曾因此写满 140G 系统盘）。

3. **旧 `tanwrt`（小写，openwrt fork）仍留在 GitHub**：
   现已不被任何 remote 引用，可保留作备份或直接删除。

4. **feeds 官方源已锁分支**：
   `feeds.conf.default` 中官方源已带 `;openwrt-25.12` 后缀，不会漂移到 `main`。
