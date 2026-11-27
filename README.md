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

**为什么按二进制能力判定而不是读 `$crashcore`**：ShellCrash 有 7 处 `crashcore=meta` 兜底（`init.sh`、`bfstart.sh`、`9_upgrade.sh` 多处）。如果按配置判断，一旦配置和实际内核不一致（首次安装常见），就会走错分支。看二进制实际能力没有这个问题。

## 已知不支持

| 功能 | 原因 |
|---|---|
| **自定义入站**（`listeners`：vmess-in / ss-in） | concord 明确不打开 `listeners`。默认关闭，开启后该功能静默失效，不影响其他 |
| **PAC** | concord 无 PAC 服务 |
| **`tun.stack`** | 只有自己的 userspace 栈，配置里的值被忽略 |

## 跟上上游更新

ShellCrash 上游更新频繁。本仓库的做法是 **全量代码 + 补丁双轨**：

- 别人 `git clone` 就能直接用（`ShellCrash/` 是全量的）
- 每周一 `sync-upstream.yml` 自动拉上游 → 应用 `patches/shellcrash-concord.patch` → 通过则提交
- **补丁打不上时不开 PR、不静默失败，而是自动开 issue 报警**，issue 里写了三处改动分别是什么、怎么重新生成补丁

补丁过期是迟早的事（上游改了 `core_check` 之类就会冲突）。那时候按 issue 里的步骤，重新 diff 一次生成补丁即可，通常几分钟。

## 许可

`install.sh` 与本仓库的 workflow 为 MIT。分发的 concord 二进制采用其上游许可（GPL-3.0-or-later），见 [chen08209/concord](https://github.com/chen08209/concord)。
