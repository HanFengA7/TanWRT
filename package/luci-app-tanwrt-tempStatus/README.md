# luci-app-tanwrt-tempStatus

OpenWrt 25.12 (LuCI2) 温度监控插件：实时显示 CPU / 主板温度，提供历史趋势曲线与阈值告警。

## 功能

- **实时状态页**：`状态 → 温度`，卡片式展示所有传感器（hwmon + thermal_zone 自动探测），3s 轮询
- **首页集成**：利用 25.12 官方扩展点（`view/status/include/` 动态扫描），首页 System 区下方自动出现"温度"卡片，**无需 patch 任何官方文件**
- **趋势曲线**：`状态 → 温度历史`，手写 SVG 折线图（零依赖），1h / 6h / 24h 范围切换，hover 显示数值
- **阈值告警**：warn/crit 两级，超标时页面顶部红色横幅 + 卡片变色；阈值可在页面配置，即时生效

## 架构

纯 LuCI2 技术栈：**JS 视图（前端）+ ucode RPC（后端）+ uci 配置**，无 Lua、无常驻进程。

```
/sys/class/hwmon + /sys/class/thermal
        ↓  (RPC get_sensors 调用时扫描，并顺带写入)
/tmp/tanwrt_temp/history.json（环形缓冲，默认 24h）
        ↓
rpcd · tanwrt-temp.uc（get_sensors / get_history / get_config / set_config）
        ↓
LuCI2 JS 视图：状态页 / 趋势页 / 首页卡片（页面轮询驱动）
```

- 历史数据**由前端轮询驱动**：任一页面（状态页 / 趋势页 / 首页）打开时即触发采样；全关页面时无新数据，属预期行为
- 历史存 `/tmp`（tmpfs，重启清空，零 flash 磨损）
- 同秒内多页面并发请求自动去重，只记一个点

## 目录结构

```
luci-app-tanwrt-tempStatus/
├── Makefile
├── root/
│   ├── etc/config/tanwrt_temp              # 默认配置
│   └── usr/share/
│       ├── luci/menu.d/…json               # 菜单
│       ├── rpcd/acl.d/tanwrt-temp.json     # RPC 权限
│       └── rpcd/ucode/tanwrt-temp.uc       # 后端：采集 + 历史 + 配置
├── htdocs/luci-static/resources/
│   ├── tanwrt/tempstatus.js                # 前端共享模块（RPC 封装）
│   └── view/
│       ├── tanwrt/tempstatus/status.js     # 状态页
│       ├── tanwrt/tempstatus/history.js    # 趋势页
│       └── status/include/65_tanwrt_temp.js  # 首页卡片（官方扩展点）
├── po/                                     # en / zh-cn
└── README.md
```

## 编译接入（TanWRT 轻 fork）

### 方式一：独立 feed 仓库（推荐）

```bash
# 1. 在 TanWRT 的 feeds.conf 增加引用
echo 'src-git tanwrt_pkgs https://github.com/<you>/tanwrt-packages.git' >> feeds.conf

# 2. 更新并安装
./scripts/feeds update tanwrt_pkgs
./scripts/feeds install luci-app-tanwrt-tempStatus

# 3. 选中并编译
make menuconfig  # LuCI → Applications → luci-app-tanwrt-tempStatus
make -j$(nproc)
```

### 方式二：临时本地路径（开发调试）

```bash
# 放到源码树任意目录后 src-link
echo 'src-link tanwrt_pkgs /path/to/packages' >> feeds.conf
./scripts/feeds update tanwrt_pkgs && ./scripts/feeds install luci-app-tanwrt-tempStatus
```

安装：`apk add luci-app-tanwrt-tempStatus`（固件内置则无需安装）。

## 配置（/etc/config/tanwrt_temp）

| 项 | 默认 | 说明 |
|---|---|---|
| `sample_interval` | 5 | 历史采样最小间隔（秒），同秒去重 |
| `history_hours` | 24 | 历史保留时长（小时） |
| `page_refresh` | 3 | 状态页刷新间隔（秒） |
| `warn_temp` / `crit_temp` | 70 / 85 | 全局告警阈值（°C） |
| `enable_homepage` | 1 | 首页是否显示温度卡片 |
| `sensor` 段 | — | 按 `chip`（hwmon name）+ `label`（temp*_label）匹配，覆盖 `alias` 显示名与 warn/crit 阈值；`label` 留空匹配该芯片全部通道 |

## 目标机传感器核实（编码/排障第一步）

在**目标机**（运行 TanWRT 的机器，非编译服务器）上执行：

```sh
# hwmon 芯片与通道
for h in /sys/class/hwmon/hwmon*; do
  echo "== $(cat $h/name): $h"
  grep -H . $h/temp*_label 2>/dev/null
done
# ACPI 热区
for z in /sys/class/thermal/thermal_zone*; do echo "$z: $(cat $z/type) $(cat $z/temp)"; done
```

根据输出在 `/etc/config/tanwrt_temp` 补 `sensor` 段即可得到正确的别名与阈值。
注意：x86 上 CPU 核心温度一般来自 `coretemp`（Intel）/ `k10temp`（AMD）；主板 SuperIO 芯片（如 `nct6775`）如未出现，需在内核配置中启用对应驱动。

## 已知限制

- 历史数据不跨重启（`/tmp`），且仅在页面打开时采集
- `get_sensors` 每次调用会重写整个历史文件（24h 数据约 1–2MB，tmpfs 内可接受；如需进一步优化可做降采样）
- 首页卡片与 `10_system.js` 等同级组件由官方 `index.js` 统一轮询，间隔由 LuCI 框架决定（约 5s）

## 开发验证清单

1. `apk add` / 固件内置后，菜单出现"温度 / 温度历史"
2. 状态页数值 3s 刷新，告警横幅与卡片变色随阈值变化
3. 趋势页 1h/6h/24h 曲线正常，hover 显示数值
4. 首页出现"温度"卡片，`enable_homepage=0` 时隐藏
5. 阈值修改保存后 `uci show tanwrt_temp` 生效
