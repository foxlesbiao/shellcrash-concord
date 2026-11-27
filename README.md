# shellcrash-concord

把 [concord](https://github.com/chen08209/concord)（Rust 写的代理内核）装进 [ShellCrash](https://github.com/juewuy/ShellCrash)，用于 OpenWrt 路由器。

**它解决什么问题**：ShellCrash 默认用 mihomo（Go）。concord 是照着 mihomo 行为重写的 Rust 内核，同样配置能直接跑，内存占用约为 mihomo 的 40%。

---

## 工作原理

不自己编译，而是**从 [nikki-concord](https://github.com/user-7392/nikki-concord) 的 release 里提取静态链接的 aarch64 内核**，重新发布成本仓库的 release。

```
nikki-concord release (.ipk)
        │  Actions 每周一自动拉取、解包
        ▼
  concord-aarch64.gz  ← 本仓库 release
        │  install.sh
        ▼
  路由器 CrashCore.raw
```

这么做的三个理由：

1. **上游已经打好 OpenWrt 补丁**：低内存 jemalloc 调优、`release_free_memory()` 主动退页、测速并发限流、Mihomo 未知字段静默忽略等。自己从上游 concord 编译**没有**这些。
2. **免掉 BoringSSL + LTO 的 30–60 分钟编译**，以及 8GB 内存机器上的 OOM 风险。
3. **自动跟随上游版本**，不必自己维护编译链。

---

## 安装

在路由器上执行（需要已装好 ShellCrash）：

```sh
sh install.sh
```

脚本会：下载 → 校验 sha256 → 备份原内核 → 替换 `CrashCore.raw` → 改写 `command.env` 与 `clash_modify.sh` 的启动参数 → 重启 → 自检代理是否通。

指定版本：

```sh
sh install.sh v0.1.0-r28
```

## 回滚

```sh
sh install.sh --rollback
```

恢复 `CrashCore.raw.mihomo.bak` 及相关脚本备份。首次安装时自动创建这些备份。

---

## 实测数据（IPQ9554，ShellCrash 1.9.5beta4）

| 维度 | mihomo | concord |
|---|---|---|
| 单流 100MB | 6.67 MB/s | 6.67 MB/s |
| 16/32/64 路并发 | 9.4 / 10.0 / 10.0 MB/s | 9.4 / 10.3 / 10.5 MB/s |
| 延迟（100 并发） | 1.481s | 1.430s |
| Loopback 极限 | 344.8 MB/s | 285.8 MB/s |
| **内存 RSS** | 53.4 MB | **21.6 MB** |
| **CPU（100 并发）** | 42 jiffies | **22 jiffies** |

**结论：延迟、吞吐、并发三项持平，唯一确定的收益是资源占用减半。**

在家宽 + 共享专线环境里，瓶颈是节点带宽（约 84 Mbps），换内核不会让网速变快。如果你的动机是"延迟更低"，这个方案帮不上；如果想让路由器省点内存/CPU，它是对的。

---

## 已知限制

| 项 | 情况 |
|---|---|
| **内置面板** | ⚠️ concord 不提供静态文件（`/ui` 返回 501 `{"message":"not supported by Concord"}`）。**已自动解决**：`install.sh` 用路由器自带的 `uhttpd` 托管 ShellCrash 下载的同一份面板，地址变成 `http://<路由器IP>:8090/`，菜单里的面板链接也同步改好了 |
| **PAC** | ❌ concord 无 PAC 服务，菜单里那行 PAC 地址已隐藏 |
| **TUN stack** | ⚠️ concord 只有自己的 userspace 栈，配置里的 `tun.stack` 被忽略。实测 `utun` 设备能正常创建（`198.18.0.1/30`），但 TUN 模式的完整转发未实测（当前走 tproxy） |
| **glibc 二进制** | ✅ 已解决：本仓库提供的是静态链接版本，不依赖 libc |
| **架构** | 仅 `aarch64`（`aarch64_cortex-a53/a72/generic` 共用）。需要 x86_64 时，上游 ipk 里有对应产物，改 `CONCORD_RELEASE` 即可 |

### 面板怎么救

```sh
uhttpd -p 0.0.0.0:8090 -h $CRASHDIR/ui
# 浏览器打开 http://<路由器IP>:8090/ ，后端地址填 <路由器IP>:9999
```

写进 `/etc/rc.local` 可开机自启（注意加 `sleep` 等 USB 挂载完成）。

---

## 为什么不用别的方案

| 方案 | 为什么不行 |
|---|---|
| FlClash `-rs` 版 deb 里的内核 | glibc 动态链接，OpenWrt（musl）跑不了；且需宿主 token |
| clash-rs | 读不了 mihomo 完整配置：`proxy-groups` 的 url-test/load-balance/fallback 和整块 `dns` 都解析失败 |
| 直接吃 nikki-concord 的 OpenWrt 包 | 要求 OpenWrt 23.05+/24.10（firewall4 + nftables），老固件装不上；本方案只取其中的内核二进制 |
| 自己 `cargo zigbuild` | 可行，但没有上游的 OpenWrt 适配补丁，且 CI 上 7GB runner 编译 LTO 容易 OOM |

---

## 仓库结构

```
.github/workflows/sync.yml          # 每周一同步 concord 内核 → 发布 release
.github/workflows/sync-upstream.yml # 每周一拉上游 ShellCrash → 应用补丁 → 提交；冲突则开 issue
patches/shellcrash-concord.patch    # 对 ShellCrash 的全部改动（3 个文件）
ShellCrash/                          # 全量 ShellCrash 源码（已打补丁）
install.sh                           # 路由器端安装/回滚脚本
```

## 改动了 ShellCrash 的哪些地方

9 个文件、204 行，全部在 `patches/shellcrash-concord.patch` 里。按作用分四类：

**内核识别与校验**

| 文件 | 函数 | 改动 |
|---|---|---|
| `scripts/libs/core_tools.sh` | `core_check()` | 先探测二进制是否 concord（`run -h` 输出含 `concord`），是则用 `run -c ... -d ...` 启动 |
| `scripts/starts/clash_modify.sh` | `test_yaml()` | concord 的 `-t` 只接受 `-c <file>`，不接受 mihomo 的 `-d/-f` |
| `scripts/starts/clash_modify.sh` | `prepare_clash_base_config()` | concord 归一化为 meta，复用整套 mihomo 配置生成逻辑 |

**防止被自动换回 mihomo**

| 文件 | 改动 |
|---|---|
| `scripts/starts/clash_check.sh` | 订阅含 vless/hysteria 时**不再自动换内核**（concord 原生支持这两种协议） |
| `scripts/starts/core_config.sh` | UA 用 `clash.meta/mihomo` 而非 `clash`（部分订阅服务器按 UA 拒绝） |
| `scripts/init.sh` | **每次更新脚本都会重写 `configs/command.env`**。原来只认 singbox/mihomo，concord 会拿到 mihomo 的 `-d/-f` 启动命令直接起不来。加 concord 分支 |
| `scripts/libs/core_tools.sh` `core_find()` | 启动时找内核用 `find CrashCore.* \| head -1`，顺序不定，可能选中 `.raw.mihomo.bak`。改为优先 `CrashCore.raw` 并排除 `.bak` |

**面板与显示**

| 文件 | 改动 |
|---|---|
| `scripts/menu.sh` | 面板地址 `:db_port/ui` → `:8090`；内核名显示 `Concord` |
| `scripts/menus/1_start.sh` | 隐藏 PAC 地址（concord 无 PAC 服务） |
| `scripts/menus/9_upgrade.sh` | 面板安装后把 hostdir 归一成 `:8090`；内核类型菜单只留 Concord |

**内核专属功能放行**

| 文件 | 改动 |
|---|---|
| `scripts/menus/6_core_config.sh` | 本地节点管理（providers）不再只认 meta/singboxr |
| `scripts/menus/dns.sh` | DNS 模式（mix/route）设置不再拒绝 concord |

**砍掉 concord 不支持的功能**

| 文件 | 改动 |
|---|---|
| `scripts/menus/7_gateway.sh` | 删掉「VMess 入站」「Shadowsocks 入站」两个菜单项及其子菜单（共 265 行）。这两项靠 `listeners`，concord 不打开。Tailscale/WireGuard 编号上移为 4/5 |
| `scripts/starts/clash_modify.sh` | `add_custom_inbounds_and_rules()` 里跳过 `listeners` 生成——即使配置里残留 `vms_service=ON`，也不会往配置里写无用的 `listeners:` 段 |
| `scripts/menus/9_upgrade.sh` `setcore()` | 菜单只剩 1) 更新 Concord / 2) CPU 架构 / 3) 重新下载，父菜单叫「更新内核」 |
| `scripts/menus/9_upgrade.sh` `setcoretype()` | 原来是个只有一项的「选择内核」交互，改成直接 `crashcore=concord` |
| `scripts/menus/9_upgrade.sh` | 删掉 `setcustcore()` / `checkcustcore()` / `setziptype()`（约 144 行），自定义内核源整块移除 |
| `scripts/menus/9_upgrade.sh` | 「更新 Concord」按 `$cpucore` 选对应架构内核；删掉「切换安装源」（`get_bin` 已钉死 `update_url`，改了无效），卸载/感谢重编号为 7/8 |
| `scripts/menus/providers_{clash,singbox}.sh` | 模板下载失败时不再回落到 `setserver`（源已固定），改为提示检查网络 |
| `scripts/menus/9_upgrade.sh` `checkcustgeo()` | geo 数据源按内核过滤：concord 只列 `Country.mmdb` 和 `.mrs`，不列 `GeoIP.dat`/`GeoSite.dat`/`.srs`（它读不了） |
| `scripts/menus/9_upgrade.sh` `setcustgeo()` | concord 下隐藏 dat/srs 三个数据源，只留 meta-rules-dat(mmdb) 和 ruleset_geodata(mrs) |

**为什么按二进制能力判定而不是读 `$crashcore`**：ShellCrash 有 7 处 `crashcore=meta` 兜底（`init.sh`、`bfstart.sh`、`9_upgrade.sh` 多处）。如果按配置判断，一旦配置和实际内核不一致（首次安装常见），就会走错分支。看二进制实际能力没有这个问题。

## 纯 concord：删掉了什么

本 fork 只跑 concord，所以所有 sing-box / mihomo 专属的东西都删了：

| 删除项 | 内容 |
|---|---|
| `starts/singbox_modify.sh` | 495 行，sing-box 多 JSON 配置生成 |
| `starts/singbox_config_check.sh` | 37 行 |
| `starts/singbox_check.sh` | 10 行 |
| `menus/providers_singbox.sh` | 137 行，订阅模板生成 |
| `libs/meta_listeners.sh` | 27 行，自定义入站（listeners） |
| `bin/meta` `bin/singboxp` `bin/singboxr` | **201MB** 各架构预编译内核，本 fork 永远不会下载 |
| `singbox_providers.list` | sing-box 模板列表 |

合计 **706 行代码 + 201MB 二进制**，仓库从 226M 降到 27M。

**保留的 mihomo 代码**：`core_tools.sh` / `clash_modify.sh` / `init.sh` 里的 mihomo 分支**不能删**——`install.sh --rollback` 靠它们生成 `-d/-f` 启动命令切回 mihomo。删了就没有退路。

配置层面对 sing-box 的处理：`bfstart.sh` 一旦发现 `crashcore=singbox*` 会直接报错退出，而不是去 source 一个已经被删的文件。

## 多架构

release 里每个架构各发一个内核，菜单和安装脚本都会按当前 CPU 自动选：

| 架构 | 来源 | 大小 |
|---|---|---|
| `aarch64_generic` | nikki-concord ipk | 12.7MB |
| `aarch64_cortex-a53` | 同上 | 12.7MB |
| `aarch64_cortex-a72` | 同上 | 12.7MB |
| `x86_64` | 同上 | 13.4MB |

映射规则：

- 菜单「更新内核」→ 按 ShellCrash 的 `$cpucore`：`arm64` → `aarch64_generic`，`amd64` → `x86_64`
- `install.sh` → 按 `uname -m`，可用 `CONCORD_ARCH=...` 覆盖
- 不支持的架构会明确提示，不会下错二进制

历史遗留的 `concord-aarch64.gz` 已从 release 删除，现在只有 `concord-<arch>.gz`。

## 已知不支持

| 功能 | 处理 |
|---|---|
| **自定义入站**（`listeners`：vmess-in / ss-in） | **已从菜单删除**，配置生成也不再写 `listeners:` |
| **Tailscale / WireGuard** | 是 sing-box 内核的 `endpoints` 功能（`sb_endpoints.sh` + `singbox_modify.sh`），不是独立进程，concord 彻底用不了。菜单保留原限制提示 |
| **PAC** | 菜单里那行地址已隐藏，concord 无 PAC 服务 |
| **GeoIP.dat / GeoSite.dat / .srs** | concord 只读 `mmdb` 和 `mrs`。geo 更新菜单已按内核过滤数据源 |
| **`tun.stack`** | 只有自己的 userspace 栈，配置里写什么都没用，但不影响运行 |

## 「更新管理脚本」已指向本仓库

菜单 `9) 更新与支持 → 1) 更新管理脚本` 现在从本仓库的 release 取 `ShellCrash.tar.gz`，不会再被上游版本覆盖。

- **每日** `sync-concord` workflow 发一个 release（concord 上游发版很快，周更会落后），同时带 **concord 内核**（4 个架构）和 **ShellCrash.tar.gz（脚本包）** + `version`
- `libs/web_get_bin.sh` 在 concord 下把 `update_url` 钉死到本仓库，并清空 `url_id`（`url_id=101` 会绕过 `update_url` 指回上游）
- 下载走 `ghfast.top` 镜像：`github.com` 在国内路由器上直连不通（实测 000 超时）
- 根目录的 `version` / `ShellCrash.tar.gz` 供 jsDelivr 兜底；`bin/`、`public/`、`rules/` 仍走 jsDelivr

更新完脚本服务会停，需要重新启动。

## 冒烟测试

```sh
# 传到路由器后跑（只读，不改任何东西）
scp smoke-test.sh root@<路由器IP>:/tmp/
ssh root@<路由器IP> sh /tmp/smoke-test.sh
```

覆盖 7 组共 51 项：

| 组 | 检查内容 |
|---|---|
| 1. 文件与配置 | 12 个脚本语法、`crashcore=concord`、6 处补丁标记是否在位、备份是否存在 |
| 2. 启动命令 | `command.env` 是否为 concord 的 `run -c` 格式 |
| 3. 进程与服务 | 进程 PID/RSS、7890/9999/8090 三个端口 |
| 4. 代理功能 | HTTPS 代理、国内站点、出口 IP、**分流（国内直连 IP vs 代理 IP）**、IPv6 出网 |
| 5. 面板 | 6 个 API 端点、面板页面、`/ui` 应返回 501、节点测速端点 |
| 6. 配置生成 | 运行配置、tun 段、节点数、rules 段、无 `listeners.yaml` |
| 7. 更新源 | release 的 `version`/`ShellCrash.tar.gz`、jsDelivr geo 数据 |

退出码 = 失败项数，可直接接 CI 或监控。

## 跟上上游更新

ShellCrash 上游更新频繁。本仓库的做法是 **全量代码 + 补丁双轨**：

- 别人 `git clone` 就能直接用（`ShellCrash/` 是全量的）
- 每周一 `sync-upstream.yml` 自动拉上游 → 应用 `patches/shellcrash-concord.patch` → 通过则提交
- **补丁打不上时不开 PR、不静默失败，而是自动开 issue 报警**，issue 里写了三处改动分别是什么、怎么重新生成补丁

补丁过期是迟早的事（上游改了 `core_check` 之类就会冲突）。那时候按 issue 里的步骤，重新 diff 一次生成补丁即可，通常几分钟。

## 许可

`install.sh` 与本仓库的 workflow 为 MIT。分发的 concord 二进制采用其上游许可（GPL-3.0-or-later），见 [chen08209/concord](https://github.com/chen08209/concord)。
