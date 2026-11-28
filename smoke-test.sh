#!/bin/sh
# shellcrash-concord 冒烟测试
# 用法: sh smoke-test.sh            # 只读检查
#       sh smoke-test.sh --full     # 额外做写操作（更新脚本/重启）
#
# 在路由器上执行（需要 root）。只读部分可随时跑。

CD="${CRASHDIR:-/mnt/usb-f9820b49/ShellCrash}"
PASS=0
FAIL=0
WARN=0

ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [ -n "$2" ] && printf '        %s\n' "$2"; }
warn() { WARN=$((WARN+1)); printf '  \033[33mWARN\033[0m  %s\n' "$1"; }
sec()  { printf '\n\033[36m== %s ==\033[0m\n' "$1"; }

# ---------- 1. 文件与配置 ----------
sec "1. 文件与配置"

[ -f "$CD/start.sh" ] && ok "ShellCrash 目录存在" || no "ShellCrash 目录不存在" "$CD"

for f in init.sh menu.sh libs/core_tools.sh libs/web_get_bin.sh starts/clash_modify.sh \
         starts/clash_check.sh starts/core_config.sh menus/1_start.sh menus/6_core_config.sh \
         menus/7_gateway.sh menus/9_upgrade.sh menus/dns.sh; do
    sh -n "$CD/$f" 2>/dev/null && ok "语法 ok: $f" || no "语法错误: $f"
done

grep -q '^crashcore=concord' "$CD/configs/ShellCrash.cfg" 2>/dev/null \
    && ok "crashcore=concord" || no "crashcore 不是 concord"

# 补丁标记
check_patch() { grep -q "$2" "$CD/$1" 2>/dev/null && ok "补丁在位: $1 ($3)" || no "补丁丢失: $1 ($3)"; }
check_patch libs/core_tools.sh        'concord'                '内核识别'
check_patch init.sh                   'crashcore=concord'      'command.env 分支'
check_patch libs/web_get_bin.sh       'shellcrash-concord'     '更新源'
check_patch menu.sh                   '8090'                   '面板地址'
check_patch starts/clash_check.sh     'concord'                'vless 不换内核'
check_patch menus/7_gateway.sh        'set_wireguard'          'WireGuard 保留'
grep -q 'set_vmess' "$CD/menus/7_gateway.sh" 2>/dev/null \
    && no "7_gateway 里 set_vmess 还在" || ok "自定义入站已删"

# 纯 concord：不应该有任何 mihomo 备份
[ -f "$CD/CrashCore.raw.mihomo.bak" ] && no "仍有 mihomo 内核备份（不是纯 concord）" || ok "无 mihomo 内核备份（纯 concord）"
[ -d "$CD/.orig" ] && no "仍有 .orig 备份目录" || ok "无 .orig 备份目录"

# 不该有 sing-box 专用脚本
SB=$(ls "$CD/starts" "$CD/menus" "$CD/libs" 2>/dev/null | grep -ci 'singbox\|core_exchange')
[ "${SB:-0}" -eq 0 ] && ok "无 sing-box 专用脚本" || no "还有 $SB 个 sing-box 脚本"

# ---------- 2. 启动命令 ----------
sec "2. 启动命令"

if grep -q 'CrashCore run -c' "$CD/configs/command.env" 2>/dev/null; then
    ok "command.env 是 concord 格式"
else
    no "command.env 不是 concord 格式" "$(cat "$CD/configs/command.env" 2>/dev/null)"
fi

# ---------- 3. 进程与服务 ----------
sec "3. 进程与服务"

PID=$(pgrep -f 'CrashCore run -c' | head -1)
if [ -n "$PID" ]; then
    ok "concord 进程运行中 (PID $PID)"
    RSS=$(awk '/VmRSS/{print $2}' "/proc/$PID/status" 2>/dev/null)
    [ -n "$RSS" ] && printf '        RSS %s kB (%.1f MB)\n' "$RSS" "$(echo "$RSS" | awk '{print $1/1024}')"
else
    no "concord 进程未运行"
fi

for port in 7890 9999 8090; do
    netstat -lnt 2>/dev/null | grep -q ":$port " && ok "端口 $port 监听中" || no "端口 $port 未监听"
done

# ---------- 4. 代理功能 ----------
sec "4. 代理功能"

P=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -x http://127.0.0.1:7890 https://www.gstatic.com/generate_204 2>/dev/null)
[ "$P" = "204" ] && ok "HTTPS 代理 (gstatic 204)" || no "HTTPS 代理失败" "code=$P"

P=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -x http://127.0.0.1:7890 http://www.baidu.com 2>/dev/null)
[ "$P" = "200" ] && ok "国内站点直连 (baidu 200)" || no "国内站点失败" "code=$P"

IP=$(curl -s --max-time 20 -x http://127.0.0.1:7890 https://api.ipify.org 2>/dev/null)
[ -n "$IP" ] && ok "出口 IP: $IP" || no "取不到出口 IP"

# 规则分流：国外域名走代理出口，国内域名走直连（家宽 IP）
# DIRECT 的流量不进 /connections 记录，所以用出口 IP 对比来判断
IP_FOREIGN=$(curl -s --max-time 20 -x http://127.0.0.1:7890 https://api.ipify.org 2>/dev/null)
IP_CN=$(curl -s --max-time 20 -x http://127.0.0.1:7890 https://cip.cc 2>/dev/null \
    | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
if [ -n "$IP_CN" ] && [ -n "$IP_FOREIGN" ]; then
    if [ "$IP_CN" != "$IP_FOREIGN" ]; then
        ok "分流生效: 国内 $IP_CN (直连) / 国外 $IP_FOREIGN (代理)"
    else
        warn "分流可疑: 国内国外出口相同 ($IP_FOREIGN)"
    fi
else
    warn "取不到分流对照 IP（国内=$IP_CN 国外=$IP_FOREIGN）"
fi

# IPv6：用户明确要求保留，链路断了要报
IP6=$(curl -s --max-time 15 -6 https://api64.ipify.org 2>/dev/null || curl -s --max-time 15 -6 https://ipv6.icanhazip.com 2>/dev/null)
[ -n "$IP6" ] && ok "IPv6 出网正常: $(echo $IP6 | head -c 30)" || warn "IPv6 出网失败（用户要求保留 v6，需排查）"

# ---------- 5. 面板 ----------
sec "5. 面板"

for ep in proxies configs connections traffic version memory; do
    C=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://127.0.0.1:9999/$ep" 2>/dev/null)
    [ "$C" = "200" ] && ok "API /$ep 200" || no "API /$ep 异常" "code=$C"
done

C=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://127.0.0.1:8090/" 2>/dev/null)
[ "$C" = "200" ] && ok "面板页面 8090 200" || no "面板页面异常" "code=$C"

T=$(curl -s --max-time 8 "http://127.0.0.1:8090/" 2>/dev/null | grep -o '<title>[^<]*</title>')
[ -n "$T" ] && ok "面板标题: $T" || warn "取不到面板标题"

# concord 应拒绝 external-ui
C=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://127.0.0.1:9999/ui/" 2>/dev/null)
[ "$C" = "501" ] && ok "/ui 返回 501（符合 concord 行为）" || warn "/ui 返回 $C（预期 501）"

# 测速端点
C=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "http://127.0.0.1:9999/proxies/DIRECT/delay?timeout=3000&url=http%3A%2F%2Fwww.gstatic.com%2Fgenerate_204" 2>/dev/null)
[ "$C" = "200" ] && ok "节点测速端点可用" || no "测速端点异常" "code=$C"

# ---------- 6. 配置生成 ----------
sec "6. 配置生成"

[ -f /tmp/ShellCrash/config.yaml ] && ok "运行配置已生成" || no "运行配置不存在"
if [ -f /tmp/ShellCrash/config.yaml ]; then
    grep -q '^tun:' /tmp/ShellCrash/config.yaml && ok "tun 段存在" || warn "无 tun 段"
    N=$(grep -c '^  - {' /tmp/ShellCrash/config.yaml 2>/dev/null)
    if [ "${N:-0}" -gt 0 ]; then ok "代理节点数: $N"; else no "配置文件里没有代理节点"; fi
    N=$(grep -c '^rules:' /tmp/ShellCrash/config.yaml 2>/dev/null)
    [ "$N" -gt 0 ] && ok "rules 段存在" || warn "无 rules 段"
fi

[ -f /tmp/ShellCrash/listeners.yaml ] && warn "listeners.yaml 存在（concord 不支持）" || ok "无 listeners.yaml（符合预期）"

# ---------- 7. 更新源可达 ----------
sec "7. 更新源"

REL='https://gh-proxy.com/https://github.com/foxlesbiao/shellcrash-concord/releases/latest/download'
for f in version ShellCrash.tar.gz; do
    C=$(curl -sL -o /dev/null -w '%{http_code}' --max-time 45 "$REL/$f" 2>/dev/null)
    [ "$C" = "200" ] && ok "release/$f 可达" || no "release/$f 不可达" "code=$C"
done

V=$(curl -sL --max-time 30 "$REL/version" 2>/dev/null)
[ -n "$V" ] && ok "远端版本: $V" || no "取不到远端版本"

J='https://testingcf.jsdelivr.net/gh/foxlesbiao/shellcrash-concord@main/ShellCrash/bin/geodata/cn_mini.mmdb'
C=$(curl -sL -o /dev/null -w '%{http_code}' --max-time 45 "$J" 2>/dev/null)
[ "$C" = "200" ] && ok "jsDelivr geo 数据可达" || no "jsDelivr geo 不可达" "code=$C"

# ---------- 汇总 ----------
printf '\n\033[36m== 汇总 ==\033[0m\n'
printf '  PASS %s   WARN %s   FAIL %s\n' "$PASS" "$WARN" "$FAIL"
[ "$FAIL" -eq 0 ] && printf '\033[32m冒烟测试通过\033[0m\n' || printf '\033[31m有 %s 项失败\033[0m\n' "$FAIL"
exit "$FAIL"
