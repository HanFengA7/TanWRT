# 集成第三方软件包（以 luci-app-oxidns 为例）

本仓库把第三方包以 **in-tree package（直接放 package/ 目录）** 方式集成，而不是 OpenWRT 标准的 feeds 方式。原因见末尾「为什么不用 feeds」。

## 已集成的包

| 包 | 位置 | 说明 |
|---|---|---|
| `luci-app-oxidns` | `package/luci-app-oxidns/` | OxiDNS 的 LuCI 管理页（Services -> OxiDNS）。runtime 的 OxiDNS 内核由插件首次运行时从 GitHub Releases 下载，不在固件内 |

两个 target（x86/64、NanoPi R5C）的 `config*.seed` 都已 `CONFIG_PACKAGE_luci-app-oxidns=y`，`build.sh` 编译时自动带入。

## 怎么加一个新的第三方包（in-tree 方式）

1. 把包源码放到 `package/<包名>/`，只保留编译需要的文件（Makefile、po、files、src 等），删掉上游仓库的 README/AGENTS/.github 等非编译文件。
2. 确保包的 Makefile 里对 `luci.mk` 等外部 include 用绝对路径 `include $(TOPDIR)/feeds/luci/luci.mk`（package/ 扫描阶段 `$(TOPDIR)` 已正确定义，能展开）。
3. 在对应的 `config*.seed` 末尾加 `CONFIG_PACKAGE_<包名>=y`。
4. 本地验证：`cp config.seed .config && make defconfig && grep CONFIG_PACKAGE_<包名>= .config` 应看到 `=y`；再 `make package/<包名>/compile` 应出 `.apk`。
5. 提交：`git add package/<包名> config*.seed && git commit && git push --force-with-lease origin tanwrt-25.12`。

## 怎么更新第三方包到上游新版本

`package/<包名>/` 是我们跟踪的一份快照，更新需手动同步上游：

```bash
cd /home/tc/op/openwrt
rm -rf package/<包名>/.git            # 若之前带 git
git clone --depth 1 <上游 URL> /tmp/pkg-src
rm -rf /tmp/pkg-src/.git
cp -r /tmp/pkg-src/. package/<包名>/
# 删掉非编译文件：README* AGENTS.md .github .gitignore 等
git add package/<包名> && git commit -m "bump: <包名> to <版本>" && git push --force-with-lease origin tanwrt-25.12
```

## 为什么不用 feeds（src-git / src-dir）

OpenWRT 25.12 的 `scripts/feeds` 在 `update` 阶段用**静态文本扫描**生成包索引，不会展开 Makefile 里 `include` 的外部文件（如 `luci.mk`）。`luci-app-*` 类的包其真正的 `define Package/...` 是在 `luci.mk` 里靠 `$(eval $(call Package,...))` 运行时生成的，feeds 扫描器看不到 → 包永远 0 个、无法选入。

而直接放 `package/` 目录下时，OpenWRT 的扫描会**真正 make 提取 metadata**，能正确展开 `luci.mk` 并注册包。因此本仓库统一用 in-tree package 方式集成第三方 luci-app。

> 注：如果未来某个包的 Makefile 是标准 `define Package/xxx ... endef` 写法（不依赖外部 include 展开），那它用 feeds 方式也能正常集成；luci-app 类因依赖 `luci.mk` 故走 in-tree 更稳。
