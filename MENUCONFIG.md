# 用 make menuconfig 手动编译教程

这份文档讲**脱离 `build.sh` 自动流水线**、用 `make menuconfig` 交互式改配置并手动编译的完整流程。
适合场景：想临时加/减软件包、调内核模块、改分区大小，先本地验证再决定是否提交到 `config*.seed`。

> 核心约定：`.config` 是**生成的**，真正的定制记录在版本库里的 `config.seed`（x86/64）或 `config-r5c.seed`（NanoPi R5C）。
> `build.sh` 每次都 `cp config*.seed .config && make defconfig`，所以**直接改 `.config` 不回灌，下次跑 `build.sh` 会被覆盖**。

---

## 0. 前置

```bash
cd /home/tc/op/openwrt
git status --short          # 工作树应是干净的；有改动先 stash/commit
df -h /                    # 确认系统盘空闲 > 20G（构建中间产物很大）
df -h /tmp                 # /tmp 是 3.9G tmpfs 内存盘，编到一半被它撑满会报 No space left on device
```

---

## 1. 选目标并还原基准 .config

x86/64（默认）：

```bash
cp config.seed .config
```

NanoPi R5C（rockchip/armv8）：

```bash
cp config-r5c.seed .config
```

> 千万别漏这步——不先 `cp` 就 `menuconfig`，会基于上一次的 `.config` 改，可能进错架构（x86 和 rockchip 是两套 target，一份 `.config` 只能编一个）。

---

## 2. 打开 menuconfig 改配置

```bash
make menuconfig
```

TUI 操作：
- 方向键移动；`Enter` 进入子菜单；`Esc Esc` 返回上层
- `Y` / `N` / `M`：编译进固件 / 不编译 / 编译成模块（kmod）
- `/`：搜索符号（如搜 `r8169`、`luci`、`kmod-rtl*`），按数字跳转定位
- 改完后选 `Save`（默认写回 `.config`），`Exit` 退出

常见改动示例：
- 加 LuCI 应用：`` Network `` → `Routing` 之类；或搜 `luci-app-*`
- 加 WiFi 驱动：`` Kernel modules `` → `Wireless Drivers` → `kmod-mt7915e`（MT79xx）等
- 改根分区大小：`Target Images` → `Root filesystem partition size (MiB)`（当前 4096；**注意见第 5 节内存坑**）
- 关掉某个包：`N` 取消即可

---

## 3. 把改动回灌成 seed（关键，否则白改）

退出 menuconfig 后，把当前 `.config` 的差异**反向**导出成新的 seed，覆盖旧文件：

```bash
./scripts/diffconfig.sh > config.seed        # x86 改了就覆盖 config.seed
# 或 R5C：
./scripts/diffconfig.sh > config-r5c.seed
```

`diffconfig.sh` 只输出相对默认配置的差异，正好就是 `config*.seed` 应有的内容。
**这步决定你的改动能否进版本库、能否被 `build.sh` 复现。**

如果只想临时编来验证、暂不提交，可以跳过本步，但下次 `cp config*.seed .config` 会丢失未回灌的改动。

---

## 4. 编译

先生成完整 `.config` 并校验依赖：

```bash
make defconfig
```

正式编译（26 核就 `-j$(nproc)`）：

```bash
make -j$(nproc)            # 想看详细错误加 V=s： make -j$(nproc) V=s
```

跨架构切换（比如刚编完 x86 现在想编 R5C）**必须清产物**，否则交叉编译产物会污染：

```bash
make clean                 # 只清 bin/build_dir 下的目标产物，保留 toolchain（快）
# 或 make dirclean         # 连 toolchain 一起清（慢但最干净）
cp config-r5c.seed .config && make defconfig && make -j$(nproc)
```

镜像产出：
- x86/64：`bin/targets/x86/64/`（含 `openwrt-x86-64-generic-squashfs-combined-efi.img.gz`）
- R5C：`bin/targets/rockchip/armv8/`（含 `openwrt-rockchip-armv8-friendlyarm_nanopi-r5c-squashfs-*.img.gz`）

---

## 5. 两个必须知道的坑

### 5.1 根分区大小受内存限制
`gen_image_generic.sh` 拼镜像时用 `dd bs=$(PARTSIZE)MiB conv=sync`，需要 **PARTSIZE 大小的连续内存**作缓冲。
构建机只有 **7.7 GiB 内存**，所以 `CONFIG_TARGET_ROOTFS_PARTSIZE` 不要超过 ~4096（4G），设 16G 会直接 `dd: memory exhausted` 失败。
（128G 目标盘的剩余空间由 OpenWRT 首次启动自动建 loop 覆盖层占满，无需把 PARTSIZE 设大。）

### 5.2 /tmp 是 3.9G 内存盘
编译写临时文件会落 `/tmp`。若它被撑满（比如误把 4G 镜像解压进 `/tmp`），feeds 建索引和编译会报 `No space left on device`。
- 查：`df -h /tmp`
- 清：`rm -f /tmp/*.img /tmp/*` 之类；校验镜像务必解压到仓库目录（如 `/home/tc/op/openwrt/_chk.img`），**绝不用 `/tmp`**

---

## 6. 验证改动是否真进固件

```bash
# 看某个包是否被选入
grep -E "CONFIG_PACKAGE_你要查的=" .config
# 看最终镜像里的包清单（APK）
ls bin/targets/x86/64/packages/ 2>/dev/null | grep -i 关键字
```

刷机/升级方式见 [README.md](README.md)。

---

## 7. 改完要留存到仓库

```bash
git add config.seed            # 或 config-r5c.seed
git commit -m "config: 加 xxx / 调 xxx"
git push --force-with-lease origin tanwrt-25.12
```

> `tanwrt-25.12` 分支日常靠 rebase 保持与官方同步，推送必须用 `--force-with-lease`（普通 push 会被拒）。
> 协作者在你 force-push 后需：`git fetch && git reset --hard origin/tanwrt-25.12`（或重新 clone）。

---

## 速查

| 想做 | 命令 |
|---|---|
| x86 基准 | `cp config.seed .config && make menuconfig` |
| R5C 基准 | `cp config-r5c.seed .config && make menuconfig` |
| 改动存回仓库 | `./scripts/diffconfig.sh > config.seed`（或 config-r5c.seed） |
| 本地编译 | `make defconfig && make -j$(nproc)` |
| 切换架构重编 | `make clean && cp 另一个seed .config && make defconfig && make -j$(nproc)` |
| 查某个包 | `grep CONFIG_PACKAGE_xxx= .config` |
