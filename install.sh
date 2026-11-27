#!/bin/sh
# shellcrash-concord 安装脚本
#
# 用法（在路由器上执行）：
#   sh install.sh               # 安装/更新（纯 concord，无回滚）
#
# 做的事：
#   1. 下载本仓库改过的脚本覆盖（见 FILES）
#   2. 删掉上游残留的 sing-box 专用脚本（见 DROP）
#   3. 写入 concord 专用配置（crashcore / custcorelink / concord_v）
#   4. 按 uname -m 下载对应架构的内核并重启，自检

set -eu

REPO="${REPO:-foxlesbiao/shellcrash-concord}"
BRANCH="${BRANCH:-main}"
# 按本机架构选内核，可用 CONCORD_ARCH 覆盖（aarch64_generic / aarch64_cortex-a53 / aarch64_cortex-a72 / x86_64）
if [ -z "${CONCORD_ARCH:-}" ]; then
    case "$(uname -m)" in
    aarch64 | arm64) CONCORD_ARCH=aarch64_generic ;;
    x86_64 | amd64)  CONCORD_ARCH=x86_64 ;;
    *) echo "[错误] 不支持的架构 $(uname -m)，可用 CONCORD_ARCH=aarch64_generic|x86_64 手动指定" >&2; exit 1 ;;
    esac
fi
# CONCORD_RELEASE 在 pick_sources() 之后按探测结果拼出来（见下）

# concord 要改的 ShellCrash 脚本（15 个，与 patches 里"修改"的部分一致）
FILES="init.sh menu.sh
libs/core_tools.sh libs/web_get_bin.sh
starts/clash_modify.sh starts/clash_check.sh starts/core_config.sh starts/bfstart.sh
menus/1_start.sh menus/6_core_config.sh menus/7_gateway.sh menus/9_upgrade.sh menus/dns.sh menus/providers_clash.sh"

# 纯 sing-box 的脚本，装上后直接删掉（concord 永远不走这些分支）
DROP="starts/singbox_modify.sh starts/singbox_check.sh starts/singbox_config_check.sh
menus/providers_singbox.sh libs/meta_listeners.sh starts/core_exchange.sh"

# ShellCrash 的运行时目录（配置/软链都在这里）
TMPDIR="${TMPDIR:-/tmp/ShellCrash}"

die()  { echo "[错误] $*" >&2; exit 1; }
info() { echo "[信息] $*"; }

# ---------- 自动选源 ----------
# GitHub 直连在国内路由器上时通时不通（实测 raw 有时 5s、有时 60s 超时），
# 每次装之前探一遍，挑最快的可用源，不用手工改 URL。
# 结果写进 RAW_BASE（脚本）和 REL_BASE（release 内核）。
probe() { # $1=URL  $2=期望的最小字节数
    _out=$(curl -sSL --max-time 8 -o /dev/null -w '%{http_code} %{time_total} %{size_download}' "$1" 2>/dev/null) || return 1
    _code=$(echo "$_out" | awk '{print $1}')
    _time=$(echo "$_out" | awk '{print $2}')
    _size=$(echo "$_out" | awk '{print $3}')
    [ "$_code" = "200" ] || return 1
    [ "${_size:-0}" -ge "${2:-1}" ] 2>/dev/null || return 1
    echo "$_time"
}

pick_sources() {
    info "探测下载源（各 8s 超时）..."
    _probe_file="ShellCrash/scripts/init.sh"
    _best_t=999; _best=""
    for base in \
        "https://ghfast.top/https://raw.githubusercontent.com/$REPO/$BRANCH" \
        "https://testingcf.jsdelivr.net/gh/$REPO@$BRANCH" \
        "https://raw.githubusercontent.com/$REPO/$BRANCH" \
        "https://cdn.jsdelivr.net/gh/$REPO@$BRANCH" ; do
        t=$(probe "$base/$_probe_file" 100) || { printf '  %-58s 不可用\n' "$(echo "$base" | cut -c1-56)"; continue; }
        printf '  %-58s %ss\n' "$(echo "$base" | cut -c1-56)" "$t"
        awk "BEGIN{exit !($t < $_best_t)}" && { _best_t=$t; _best=$base; }
    done
    [ -n "$_best" ] || die "所有下载源都不可用，检查网络"
    RAW_BASE=$_best
    info "脚本源: $RAW_BASE"

    # release 内核也探一遍（ghfast 能代理 release，jsDelivr 不能）
    _rel_gh="https://github.com/$REPO/releases/latest/download"
    _best_t=999; _best=""
    for base in "https://ghfast.top/$_rel_gh" "$_rel_gh"; do
        t=$(probe "$base/version" 1) || { printf '  %-58s 不可用\n' "$(echo "$base" | cut -c1-56)"; continue; }
        printf '  %-58s %ss\n' "$(echo "$base" | cut -c1-56)" "$t"
        awk "BEGIN{exit !($t < $_best_t)}" && { _best_t=$t; _best=$base; }
    done
    [ -n "$_best" ] || die "release 下载源都不可用"
    REL_BASE=$_best
    info "内核源: $REL_BASE"
}

find_crashdir() {
    for d in /etc/ShellCrash /mnt/*/ShellCrash /data/ShellCrash /root/ShellCrash; do
        [ -f "$d/start.sh" ] && { echo "$d"; return; }
    done
    p=$(find /mnt /data /root /opt -maxdepth 4 -name start.sh -path '*ShellCrash*' 2>/dev/null | head -1)
    [ -n "$p" ] && { dirname "$p"; return; }
    return 1
}

CRASHDIR="${CRASHDIR:-$(find_crashdir || true)}"
[ -n "$CRASHDIR" ] || die "没找到 ShellCrash，请先装官方版：https://github.com/juewuy/ShellCrash"
info "ShellCrash 目录: $CRASHDIR"
CFG="$CRASHDIR/configs/ShellCrash.cfg"

set_cfg() {
    k=$1; v=$2
    if grep -q "^$k=" "$CFG" 2>/dev/null; then
        sed -i "s|^$k=.*|$k=$v|" "$CFG"
    else
        printf '%s=%s\n' "$k" "$v" >> "$CFG"
    fi
}

# ---------- 说明 ----------
# 本版是纯 concord，不保留 mihomo 回滚路径：
#   - 不再备份 CrashCore.raw.mihomo.bak / command.env.mihomo.bak
#   - 不再保留 .orig/ 原始脚本副本
# 需要回退时，用上游 ShellCrash 重装即可。

# ---------- 选源 ----------
pick_sources
CONCORD_RELEASE="${CONCORD_RELEASE:-$REL_BASE/concord-$CONCORD_ARCH.gz}"

# ---------- 拉取改过的脚本 ----------
WORK="/tmp/scc.$$"; mkdir -p "$WORK"
info "下载 shellcrash-concord 补丁文件"
for f in $FILES; do
    url="$RAW_BASE/ShellCrash/scripts/$f"
    curl -fsSL --retry 3 --max-time 60 -o "$WORK/$(basename "$f")" "$url" || die "下载 $f 失败"
    sh -n "$WORK/$(basename "$f")" || die "$f 语法检查失败，中止"
    cp -f "$WORK/$(basename "$f")" "$CRASHDIR/$f"
    # cp -f 到已存在文件会保留旧 mode，但新建文件是 644；脚本必须可执行
    chmod +x "$CRASHDIR/$f"
done
info "补丁已应用"

# 删掉 sing-box 专用脚本（本版只跑 concord）
_dropped=0
for f in $DROP; do
    if [ -f "$CRASHDIR/$f" ]; then
        rm -f "$CRASHDIR/$f" && _dropped=$((_dropped+1))
    fi
done
[ "$_dropped" -gt 0 ] && info "已删除 $_dropped 个 sing-box 专用脚本"

# ---------- 配置 ----------
# 从 release 的 tag 取版本（concord 二进制没有 --version，asset 名也不带版本）
VER="$(curl -fsSL --max-time 30 "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
VER="${VER:-unknown}"
set_cfg crashcore    concord
set_cfg concord_v    "$VER"
set_cfg core_v       "$VER"
set_cfg custcorelink "$CONCORD_RELEASE"
info "配置: crashcore=concord custcorelink=$CONCORD_RELEASE"

# 启动命令：concord 用 run -c <config> -d <datahome>，与 mihomo 的 -d/-f 完全不同。
# 直接 cp 二进制时 core_check() 不会跑，所以这里必须显式写。
mkdir -p "$CRASHDIR/configs"
cat > "$CRASHDIR/configs/command.env" <<ENVEOF
COMMAND="\$TMPDIR/CrashCore run -c \$TMPDIR/config.yaml -d /tmp/concord-home"
ENVEOF
info "command.env: concord run -c -d /tmp/concord-home"

# ---------- 内核 ----------
mkdir -p "$TMPDIR/concord-home" 2>/dev/null || true
if ! "$CRASHDIR/CrashCore" run -h 2>&1 | grep -qi concord; then
    info "下载 concord 内核"
    curl -fsSL --retry 3 --max-time 300 -o "$WORK/concord.gz" "$CONCORD_RELEASE" || die "下载内核失败"
    gzip -dc "$WORK/concord.gz" > "$WORK/concord"; chmod +x "$WORK/concord"
    cp -f "$WORK/concord" "$CRASHDIR/CrashCore.raw"
fi

info "重启 ShellCrash"
sh "$CRASHDIR/start.sh" restart >/dev/null 2>&1 || true
sleep 12

# ---------- 面板 ----------
# concord 不支持 external-ui，用 uhttpd 托管 ShellCrash 自带的 zashboard 目录
UI_DIR="$CRASHDIR/ui"
if [ -d "$UI_DIR" ] && [ -x /usr/sbin/uhttpd ]; then
    if ! netstat -lnt 2>/dev/null | grep -q ":8090 "; then
        uhttpd -p 0.0.0.0:8090 -h "$UI_DIR" 2>/dev/null && info "面板已启动: http://<路由器IP>:8090/"
    fi
    # 开机自启（幂等：已加过就跳过）
    if [ -f /etc/rc.local ] && ! grep -q "shellcrash-concord-ui" /etc/rc.local 2>/dev/null; then
        cp -f /etc/rc.local /etc/rc.local.bak_scc 2>/dev/null || true
        cat > /tmp/scc-ui.sh <<UIEOF
#!/bin/sh
# shellcrash-concord-ui: concord 没有内置面板，用 uhttpd 托管 zashboard
( sleep 25; [ -d "$UI_DIR" ] && ! netstat -lnt 2>/dev/null | grep -q ':8090 ' && uhttpd -p 0.0.0.0:8090 -h "$UI_DIR" ) &
UIEOF
        chmod +x /tmp/scc-ui.sh
        cp -f /tmp/scc-ui.sh "$CRASHDIR/ui-server.sh"
        sed -i "/^exit 0/i $CRASHDIR/ui-server.sh # shellcrash-concord-ui" /etc/rc.local 2>/dev/null || true
        info "已设置面板开机自启"
    fi
fi

# ---------- 自检 ----------
CPID=$(pgrep -f "CrashCore run -c" 2>/dev/null | head -1 || true)
if [ -n "$CPID" ]; then
    RSS=$(awk '/VmRSS/{print $2}' "/proc/$CPID/status" 2>/dev/null || echo '?')
    info "运行中 PID=$CPID RSS=${RSS}kB"
    curl -s -o /dev/null -w "[自检] google204=%{http_code}/%{time_total}s\n" --max-time 15 \
        -x http://127.0.0.1:7890 https://www.gstatic.com/generate_204 || true
    info "完成"
else
    info "内核未启动，查看 $CRASHDIR/ShellCrash.log"
    rm -rf "$WORK"
    exit 1
fi

rm -rf "$WORK"
