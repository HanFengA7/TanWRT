# TanWRT

基于 OpenWRT 官方源码的个人维护分支，采用「路线 A」轻量维护模式：以官方为基座，把自己的定制作为增量层叠在上面，方便随时同步官方更新、也方便日后升级到下一个大版本。

## 文档导航

- [SYNC.md](SYNC.md)：同步官方更新、rebase/冲突/升级到下一大版本、多目标构建说明
- [doc/MENUCONFIG.md](doc/MENUCONFIG.md)：用 make menuconfig 手动改配置并编译的教程

## 这是什么

| 项 | 值 |
|---|---|
| 基座 | OpenWRT 官方 `openwrt-25.12` 分支 |
| 支持设备 | 1) `x86/64` Generic（64 位 x86 通用 PC / 虚拟机，EFI+BIOS）<br>2) `NanoPi R5C`（FriendlyElec，rockchip/armv8，RK3568，双 2.5GbE）|
| 包管理 | APK（`CONFIG_USE_APK=y`，opkg 已禁用）|
| 内核 | 6.12（x86 与 rockchip 在 25.12 均锁定，不可在 menuconfig 选）|
| 根分区 | 4 GiB（squashfs 只读层）|
| 自带软件 | luci、wpad-basic-mbedtls、mt76(mt7915)、RTL8125 驱动等（见各 `config*.seed`）|

> x86 镜像只含 `sda1`(16M 内核)+`sda2`(4G squashfs 只读根)；刷到 128G 盘后 OpenWRT 首次启动自动建 loop 覆盖层(rootfs_data)占满剩余≈124G。
> R5C 镜像写入 eMMC/SD，squashfs 根 + overlay，剩余空间同样由覆盖层自动用满。

## 仓库结构

| remote | 地址 | 作用 |
|---|---|---|
| `origin` | `git@github.com:HanFengA7/TanWRT.git` | 本仓库（独立仓库，非 fork）|
| `upstream` | `https://github.com/openwrt/openwrt` | 官方仓库，只读，用于同步更新 |

- 工作分支：`tanwrt-25.12`（基于官方 `openwrt-25.12` + 定制）
- `openwrt-25.12`：本地纯净跟踪官方的分支
- 配置差异：`config.seed`（x86/64）、`config-r5c.seed`（NanoPi R5C）

## 编译

```bash
git clone git@github.com:HanFengA7/TanWRT.git
cd TanWRT
git checkout tanwrt-25.12
./build.sh            # 编 x86/64
./build.sh r5c        # 编 NanoPi R5C
./build.sh all        # 依次编 x86 + R5C（中间自动 make clean，耗时翻倍）
```

镜像产出：
- x86/64：`bin/targets/x86/64/`（含 `openwrt-x86-64-generic-squashfs-combined-efi.img.gz`）
- R5C：`bin/targets/rockchip/armv8/`（含 `openwrt-rockchip-armv8-friendlyarm_nanopi-r5c-squashfs-*.img.gz`）

> x86 与 rockchip 是不同架构，一份 `.config` 只能编一个。`build.sh` 用本地标记 `.built-target` 记录上次架构，只有切换时才 `make clean`，同架构增量复用。

## 同步官方更新

一条命令即可（详见 [SYNC.md](SYNC.md)）：

```bash
./build.sh            # 默认 x86；或指定 ./build.sh r5c / all
```

`build.sh` 自动执行：拉取官方 → rebase 到 `tanwrt-25.12` → 更新 feeds → 应用对应 `config*.seed` → 编译 → 推送回本仓库。

日常手动同步（以 x86 为例，R5C 把 `config.seed` 换成 `config-r5c.seed`）：

```bash
git fetch upstream
git rebase upstream/openwrt-25.12
./scripts/feeds update -a && ./scripts/feeds install -a
cp config.seed .config && make defconfig
make -j$(nproc)
git push --force-with-lease origin tanwrt-25.12
```

> 注意：`rebase` 会改写提交哈希，推送必须用 `--force-with-lease`。协作者在你 force-push 后需 `git fetch && git reset --hard origin/tanwrt-25.12`（或重新 clone）。

## 刷机与升级

- **x86 首次刷机**：将 `bin/targets/x86/64/openwrt-x86-64-generic-squashfs-combined-efi.img.gz` 写入磁盘（`dd` / balenaEtcher / Ventoy 启动后 `dd`）。升级：`sysupgrade <img.gz>`，保持 `ROOTFS_PARTSIZE` 不变以保配置。
- **R5C 首次刷机**：将 `bin/targets/rockchip/armv8/openwrt-rockchip-armv8-friendlyarm_nanopi-r5c-squashfs-*.img.gz` 写入 eMMC/SD（参考 FriendlyElec 官方烧录方式，或在已运行的 OpenWRT 上用 `sysupgrade` 升级）。升级：`sysupgrade <img.gz>`。

## 自定义

- **配置差异**：改对应的 `config*.seed` → `make defconfig` → 提交（勿直接改 `.config`，`build.sh` 会用 `config*.seed` 覆盖它）
- **默认配置**：放进 `files/` 目录，刷机即生效
- **自有软件包**：独立 feed 仓，在 `feeds.conf` 加 `src-git` 引用
