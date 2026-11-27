# shellcrash-concord

把 ShellCrash 的代理内核换成 [concord](https://github.com/chen08209/concord) —— 一个用 Rust 重写、行为和 mihomo 一样的内核。

**一句话**：节点、订阅、分流规则全都不用改，装完照常用。换来的是路由器内存占用降到原来的一半。

---

## 适合谁

- 路由器内存紧张（512MB / 1GB 那种），跑 mihomo 时经常吃满
- 想让路由器的 CPU 轻松一点
- 已经在用 ShellCrash，不想换软件

**不适合**：如果你希望上网更快 —— 换内核不会让网速变快，瓶颈一般在节点带宽。

## 换上之后有什么区别

同一个节点、同一份配置、同一台路由器（小米 BE7000）实测：

| | mihomo（原来的） | concord（换上后） |
|---|---|---|
| 下载速度 | 6.67 MB/s | 6.67 MB/s |
| 多任务并发 | 10.0 MB/s | 10.5 MB/s |
| 网页延迟 | 135 ms | 140 ms |
| **内存占用** | **53 MB** | **22 MB** |
| **CPU（高并发时）** | 42 | **22** |

速度和延迟基本一样，**内存省 60%**，高并发时 CPU 少用一半。

---

## 安装

路由器上已经装好 ShellCrash 的话：

```sh
sh install.sh
```

脚本会自己挑最快能用的下载源，下完自动重启并检查代理是否正常。

看到 `[自检] google204=204` 就是成功了。

指定版本：

```sh
sh install.sh v0.1.0-r31
```

## 面板（网页管理界面）

原来地址是 `路由器IP:9999/ui`，换上后变成：

```
http://<路由器IP>:8090/
```

第一次打开会让你填后端地址，填 `<路由器IP>:9999`。

> 端口变了是因为 concord 不提供网页文件，改由路由器自带的 uhttpd 托管。面板还是同一个 zashboard，功能没少。

## 自动更新

**内核**：每天 13:00（北京时间）自动检查，有新版本就下载并重启。不用管。

**管理脚本**：菜单 `9) 更新与支持` → `1) 更新管理脚本`，从本仓库取，不会退回上游。

---

## 日常使用

全照旧。菜单、启停、订阅更新、分流规则、定时任务，用法和以前一样。

菜单里少了几项，是故意去掉的（这内核上用不了，留着只会误点）：

- 内核切换 —— 现在只有一个内核
- 切换安装源 —— 已固定指向本仓库
- VMess / Shadowsocks 入站
- Tailscale（不支持；WireGuard 还在）
- PAC 模式

---

## 出问题了

**代理不通**

路由器上跑：

```sh
ps w | grep CrashCore                                              # 内核在不在
curl -x http://127.0.0.1:7890 https://www.gstatic.com/generate_204 -o /dev/null -w '%{http_code}\n'
```

`204` 就是通的。`000` 说明没起来，看日志：

```sh
tail -50 /tmp/ShellCrash/ShellCrash.log
```

**面板打不开**

```sh
netstat -lnt | grep 8090
```

没有的话重启路由器，开机脚本会拉起来。

**想换回 mihomo**

重装一遍原版 ShellCrash 即可。本仓库不提供回滚 —— 保留回滚路径就得留着 mihomo 的启动代码，和"纯 concord"冲突。

---

## 自己检查装得对不对

仓库里有个只读自检脚本，不改任何东西：

```sh
sh smoke-test.sh
```

全绿（`0 FAIL`）就是装对了。

---

## 给维护者

仓库里还有三个脚本，日常用不到：

| 脚本 | 用途 |
|---|---|
| `smoke-test.sh` | 只读自检，验装得对不对 |
| `merge-upstream.sh` | 手动合并上游 ShellCrash（试打补丁，冲突则停下） |
| `regen-patch.sh` | 重新生成补丁 |

改的是 `ShellCrash/` 全量源码，改动汇总在 `patches/shellcrash-concord.patch`。

---

## 来源

这个项目没有一行代码是从零写的，全部建立在别人的工作之上：

| 部分 | 来源 | 说明 |
|---|---|---|
| 管理框架 | [juewuy/ShellCrash](https://github.com/juewuy/ShellCrash) | 菜单、启停、订阅、分流、定时任务都是它的 |
| 代理内核 | [chen08209/concord](https://github.com/chen08209/concord) | Rust 重写的 mihomo 兼容内核 |
| 内核二进制 | [user-7392/nikki-concord](https://github.com/user-7392/nikki-concord) | 已针对 OpenWrt + 低内存设备打好补丁（jemalloc 调优、主动退页、测速限流），本仓库只是从中提取并转发 |
| 网页面板 | [Zephyruso/zashboard](https://github.com/Zephyruso/zashboard) | ShellCrash 自带下载的那份 |
| 节点订阅模板 | ShellCrash 上游 | 本项目未改动 |

**性能数据怎么看**：上表所有数字都是本机实测，不是官方宣称值。

- 硬件：小米 BE7000（IPQ9554，四核 A73）
- 系统：OpenWrt 18.06，ShellCrash 1.9.5beta4
- 网络：家庭宽带 + 共享专线，节点侧带宽上限约 84 Mbps
- 方法：两个内核交替测、手动锁同一节点、测前先比对出口 IP 一致，避免比的是不同节点
- 局限：延迟和吞吐受节点波动影响大，这两项"持平"的结论比内存/CPU 那两项弱；内存和 CPU 是进程自身读数，不受网络影响

没测的部分：TUN 模式的完整转发（当前跑 tproxy）、IPv6 的极限吞吐、长期（>24h）内存泄漏。

## 许可

安装与自动化脚本为 MIT。

concord 二进制遵循上游的 GPL-3.0-or-later。

