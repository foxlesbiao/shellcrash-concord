#!/bin/sh
# shellcrash-concord 安装脚本
#
# 用法（在路由器上执行）：
#   sh install.sh               # 安装/更新
#   sh install.sh --rollback    # 回滚到 mihomo 内核
#
# 做的事：
#   1. 备份原始脚本与内核
#   2. 用本仓库改过的 3 个 scripts 覆盖（core_tools / clash_modify / 9_upgrade）
#   3. 写入 concord 专用配置（crashcore / custcorelink / concord_v）
#   4. 下载 concord 内核并重启，自检

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
CONCORD_RELEASE="${CONCORD_RELEASE:-https://ghfast.top/https://github.com/foxlesbiao/shellcrash-concord/releases/latest/download/concord-$CONCORD_ARCH.gz}"

# concord 要改的 ShellCrash 脚本（15 个，与 patches 里"修改"的部分一致）
FILES="init.sh menu.sh
libs/core_tools.sh libs/web_get_bin.sh
starts/clash_modify.sh starts/clash_check.sh starts/core_config.sh starts/bfstart.sh
menus/1_start.sh menus/6_core_config.sh menus/7_gateway.sh menus/9_upgrade.sh menus/dns.sh menus/providers_clash.sh"

# 纯 sing-box 的脚本，装上后直接删掉（concord 永远不走这些分支）
DROP="starts/singbox_modify.sh starts/singbox_check.sh starts/singbox_config_check.sh
menus/providers_singbox.sh libs/meta_listeners.sh"

# ShellCrash 的运行时目录（配置/软链都在这里）
TMPDIR="${TMPDIR:-/tmp/ShellCrash}"

die()  { echo "[错误] $*" >&2; exit 1; }
info() { echo "[信息] $*"; }

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

# ---------- 回滚 ----------
if [ "${1:-}" = "--rollback" ]; then
    [ -f "$CRASHDIR/CrashCore.raw.mihomo.bak" ] || die "没有备份，无法回滚"
    info "恢复 mihomo"
    cp -f "$CRASHDIR/CrashCore.raw.mihomo.bak" "$CRASHDIR/CrashCore.raw"
    # 用 BusyBox 兼容的写法：-not 是 GNU find 的，路由器上是 BusyBox
    for f in init.sh core_tools.sh web_get_bin.sh clash_modify.sh clash_check.sh core_config.sh \
             1_start.sh 6_core_config.sh 7_gateway.sh 9_upgrade.sh dns.sh menu.sh; do
        [ -f "$CRASHDIR/.orig/$f.orig" ] || continue
        tgt=$(find "$CRASHDIR" -name "$f" 2>/dev/null | grep -v '/\.orig/' | head -1)
        [ -n "$tgt" ] && cp -f "$CRASHDIR/.orig/$f.orig" "$tgt"
    done
    # 上游 master 把 tun stack 改成了 mips（mihomo 新版 IP stack），但 v1.19.x 报
    # "invalid tun stack" 直接起不来。回滚到 mihomo 时强制写回 system（全版本兼容）。
    for f in "$CRASHDIR/starts/clash_modify.sh" "$CRASHDIR/starts/clash_modify.sh.orig"; do
        [ -f "$f" ] && sed -i 's/stack: mips/stack: system/' "$f" 2>/dev/null
    done
    set_cfg crashcore    meta
    set_cfg custcorelink ""
    [ -f "$CRASHDIR/configs/command.env.mihomo.bak" ] && \
        cp -f "$CRASHDIR/configs/command.env.mihomo.bak" "$CRASHDIR/configs/command.env"
    cat > "$CRASHDIR/configs/command.env" <<ENVEOF
COMMAND="\$TMPDIR/CrashCore -d \$BINDIR -f \$TMPDIR/config.yaml"
ENVEOF
    sh "$CRASHDIR/start.sh" restart
    exit 0
fi

# ---------- 备份 ----------
# 内核和每个脚本分别判断：新增的补丁文件（如 init.sh）在上一次安装时不存在，
# 不能因为"内核备份已存在"就跳过它们的备份，否则回滚时恢复不了。
if [ ! -f "$CRASHDIR/CrashCore.raw.mihomo.bak" ] && [ -f "$CRASHDIR/CrashCore.raw" ]; then
    info "备份 mihomo 内核"
    cp -f "$CRASHDIR/CrashCore.raw" "$CRASHDIR/CrashCore.raw.mihomo.bak"
fi
mkdir -p "$CRASHDIR/.orig"
_bk=0
for f in $FILES; do
    o="$CRASHDIR/.orig/$(basename "$f").orig"
    if [ -f "$CRASHDIR/$f" ] && [ ! -f "$o" ]; then
        cp -f "$CRASHDIR/$f" "$o" && _bk=$((_bk+1))
    fi
done
# 备份文件里的 tun stack 也统一成 system，回滚时直接可用
for f in "$CRASHDIR"/.orig/clash_modify.sh.orig; do
    [ -f "$f" ] && sed -i 's/stack: mips/stack: system/' "$f" 2>/dev/null
done
[ "$_bk" -gt 0 ] && info "备份了 $_bk 个原始脚本到 .orig/"
[ "$_bk" -eq 0 ] && info "原始脚本已在 .orig/，不重复备份"

# ---------- 拉取改过的脚本 ----------
WORK="/tmp/scc.$$"; mkdir -p "$WORK"
info "下载 shellcrash-concord 补丁文件"
for f in $FILES; do
    url="https://raw.githubusercontent.com/$REPO/$BRANCH/ShellCrash/scripts/$f"
    curl -fsSL --retry 3 --max-time 60 -o "$WORK/$(basename "$f")" "$url" || die "下载 $f 失败"
    sh -n "$WORK/$(basename "$f")" || die "$f 语法检查失败，中止"
    cp -f "$WORK/$(basename "$f")" "$CRASHDIR/$f"
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
    info "完成。回滚: sh $0 --rollback"
else
    info "内核未启动，查看 $CRASHDIR/ShellCrash.log"
    info "回滚: sh $0 --rollback"
    rm -rf "$WORK"
    exit 1
fi

rm -rf "$WORK"
