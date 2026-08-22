# TanWRT

基于 OpenWRT 官方源码的个人维护分支，采用「路线 A」轻量维护模式：以官方为基座，把自己的定制作为增量层叠在上面，方便随时同步官方更新、也方便日后升级到下一个大版本。

## 文档导航

- [doc/SYNC.md](doc/SYNC.md)：同步官方更新、rebase/冲突/升级到下一大版本、多目标构建说明
- [doc/MENUCONFIG.md](doc/MENUCONFIG.md)：用 make menuconfig 手动改配置并编译的教程
- [doc/CUSTOM_PACKAGES.md](doc/CUSTOM_PACKAGES.md)：如何集成第三方包（如已内置的 luci-app-oxidns）

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

## 第三方包更新（内嵌于 package/）

以下第三方包以源码形式内嵌在 `package/` 下（不放 feeds，原因见 [doc/CUSTOM_PACKAGES.md](doc/CUSTOM_PACKAGES.md)），**不会自动跟随上游**，需手动同步：

| 包 | 目录 | 作用 |
|---|---|---|
| `luci-app-oxidns` | `package/luci-app-oxidns` | DoH/DoT 等 DNS 加密前端 |
| `luci-app-openclash` | `package/openclash/luci-app-openclash` | OpenClash 代理前端（含 core 依赖） |

各包版本锁定记录写在对应 `Makefile` 顶部的 `# UPSTREAM_COMMIT=` 注释里。

`build.sh` 在构建前会自动检查这些包是否有更新；你也可以单独同步：

```bash
./build.sh            # 构建前自动检查所有第三方包，有更新会逐个交互询问是否同步
./build.sh sync       # 仅检查并同步第三方包（有更新逐个交互确认，不自动提交）
./build.sh --no-check # 跳过第三方包更新检查
```

- `sync` 子命令：仅同步包、不做 rebase/feeds/编译；确认同步后会 `git add` 但不自动 commit，由你决定提交信息。
- 非交互环境（后台/管道）下不会卡住询问，仅提示去终端前台运行 `./build.sh sync`。
- 新增第三方包：在 `build.sh` 的 `PKG_NAMES` / `PKG_DIR` / `PKG_REPO` / `PKG_MK` / `PKG_SUB` 里加一项即可（详见 [doc/SYNC.md](doc/SYNC.md) 第 10 节）。

## 同步官方更新

一条命令即可（详见 [doc/SYNC.md](doc/SYNC.md)）：

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

## 默认后台地址

两份配置均未自定义 LAN，沿用 OpenWRT 默认值：

- 网页后台（LuCI）：http://192.168.1.1
- SSH / WinSCP：192.168.1.1（用户 root，首次登录无密码，须在 LuCI 或 passwd 设置）
- 设备默认 hostname：OpenWrt

> 出厂默认 LAN 网段 192.168.1.0/24。若你的上游网络也是该网段，先把电脑网口设成同段（如 192.168.1.2/24）再访问。
> 想改默认地址/网段：在 files/etc/config/network 放一份 network 配置，刷机即生效（见「自定义」）；或首次登录后直接在 LuCI 改。

## 自定义

- **配置差异**：改对应的 `config*.seed` → `make defconfig` → 提交（勿直接改 `.config`，`build.sh` 会用 `config*.seed` 覆盖它）
- **默认配置**：放进 `files/` 目录，刷机即生效
- **自有软件包**：独立 feed 仓，在 `feeds.conf` 加 `src-git` 引用
