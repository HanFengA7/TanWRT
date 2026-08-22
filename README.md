# TanWRT

基于 OpenWRT 官方源码的个人维护分支，采用「路线 A」轻量维护模式：以官方为基座，把自己的定制作为增量层叠在上面，方便随时同步官方更新、也方便日后升级到下一个大版本。

## 这是什么

| 项 | 值 |
|---|---|
| 基座 | OpenWRT 官方 `openwrt-25.12` 分支 |
| 目标 | `x86/64` Generic（64 位 x86 通用 PC / 虚拟机）|
| 镜像 | EFI + BIOS（GRUB）|
| 包管理 | APK（`CONFIG_USE_APK=y`，opkg 已禁用）|
| 内核 | 6.12（x86 目标在 25.12 锁定，不可在 menuconfig 选）|
| 根分区 | 4 GiB（squashfs 只读层）；128 GB 物理盘剩余空间由 OpenWRT 首次启动自动建 loop 覆盖层(rootfs_data)占满 |
| 自带软件 | luci 等（见 `config.seed`）|

## 仓库结构

| remote | 地址 | 作用 |
|---|---|---|
| `origin` | `git@github.com:HanFengA7/TanWRT.git` | 本仓库（独立仓库，非 fork）|
| `upstream` | `https://github.com/openwrt/openwrt` | 官方仓库，只读，用于同步更新 |

- 工作分支：`tanwrt-25.12`（基于官方 `openwrt-25.12` + 定制）
- `openwrt-25.12`：本地纯净跟踪官方的分支

## 编译

```bash
git clone git@github.com:HanFengA7/TanWRT.git
cd TanWRT
git checkout tanwrt-25.12
./build.sh
```

镜像产出在 `bin/targets/x86/64/`。

## 同步官方更新

一条命令即可（详见 [SYNC.md](SYNC.md)）：

```bash
./build.sh
```

`build.sh` 自动执行：拉取官方 → rebase 到 `tanwrt-25.12` → 更新 feeds → 应用 `config.seed` → 编译 → 推送回本仓库。

日常手动同步：

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

- **首次刷机**：将 `bin/targets/x86/64/openwrt-x86-64-generic-squashfs-combined-efi.img.gz` 写入磁盘（`dd` / balenaEtcher / 物理机用 Ventoy 启动后 `dd`）
- **磁盘占用**：镜像只含 `sda1`(16M 内核) + `sda2`(4G squashfs 只读根)。刷到 128G 盘后，OpenWRT 首次启动会在磁盘尾部剩余空间上自动创建 loop 覆盖层 `rootfs_data`（f2fs），你的配置与后续安装的软件都落在这一层，约 124G 自动可用，无需手动分区或扩容。
- **升级**：`sysupgrade openwrt-x86-64-generic-squashfs-combined-efi.img.gz`，配置默认保留（升级会备份并恢复覆盖层）。保持 `ROOTFS_PARTSIZE` 不变可确保升级后覆盖层偏移一致、配置不丢。

## 自定义

- **配置差异**：改 `config.seed` → `make defconfig` → 提交（勿直接改 `.config`，`build.sh` 会用 `config.seed` 覆盖它）
- **默认配置**：放进 `files/` 目录，刷机即生效
- **自有软件包**：独立 feed 仓，在 `feeds.conf` 加 `src-git` 引用
