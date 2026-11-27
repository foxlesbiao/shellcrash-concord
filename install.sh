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

# 不再手工维护"改过哪些文件"——补丁改了 41 个，手写列表漂移到只剩 14 个，
# lang/task_cmd/8_tools/start.sh 这些改动根本装不上。直接解 release 里的完整脚本包，
# 那一份就是"上游 + 本仓库全部改动"的结果。

# 纯 sing-box 的脚本，装上后直接删掉（concord 永远不走这些分支）
DROP="starts/singbox_modify.sh starts/singbox_check.sh starts/singbox_config_check.sh
menus/providers_singbox.sh libs/meta_listeners.sh starts/core_exchange.sh"

# ShellCrash 的运行时目录（配置/软链都在这里）
TMPDIR="${TMPDIR:-/tmp/ShellCrash}"

die()  { echo "[错误] $*" >&2; exit 1; }
info() { echo "[信息] $*"; }

# ---------- 自动选源 ----------
# GitHub 直连在国内路由器上时通时不通（实测同一 URL 有时 5s、有时 60s 超时）。
# 脚本包和内核都在 release 里，只有两条路可选：ghfast 镜像 / 直连，探一遍取快的。
pick_sources() {
    info "探测下载源..."
    _rel_gh="https://github.com/$REPO/releases/latest/download"
    # 镜像优先，不跟直连比速度。实测直连下 348KB 的脚本包能过（1.6s，比镜像快 0.2s），
    # 但下 12MB 的内核会挂住——按小文件测速选源会把大文件请求送到最不靠谱的那条线上。
    # 所以顺序固定：镜像能用就用，不能用才退直连。
    for base in "https://ghfast.top/$_rel_gh" "$_rel_gh"; do
        _name=$(echo "$base" | sed 's|^https://||; s|/.*||')
        if _size=$(curl -sSL --max-time 10 -o /dev/null -w '%{size_download}' "$base/core-version" 2>/dev/null) \
           && [ "${_size:-0}" -ge 1 ]; then
            printf '  %-58s 可用\n' "$(echo "$base" | cut -c1-56)"
            REL_BASE=$base
            info "下载源: $REL_BASE"
            return 0
        fi
        printf '  %-58s 不可用\n' "$(echo "$base" | cut -c1-56)"
    done
    die "下载源都不可用，检查网络"
}

# 大文件下载：带重试，镜像失败自动退直连
fetch() { # $1=远程文件名  $2=本地路径
    for base in "$REL_BASE" "https://github.com/$REPO/releases/latest/download"; do
        curl -fsSL --retry 2 --retry-delay 2 --max-time 180 -o "$2" "$base/$1" 2>/dev/null && return 0
        [ "$base" = "$REL_BASE" ] && info " 从 $(echo "$base" | sed 's|^https://||; s|/.*||') 下载失败，换源重试" >&2
    done
    return 1
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
info "下载 ShellCrash 脚本包"
fetch "ShellCrash.tar.gz" "$WORK/scripts.tar.gz" || die "下载脚本包失败"
mkdir -p "$WORK/scripts"
tar -xzf "$WORK/scripts.tar.gz" -C "$WORK/scripts" || die "解包失败"
# 解出来的就是 $CRASHDIR 的内容结构（init.sh / libs/ / menus/ / starts/ / lang/ ...）
for f in "$WORK"/scripts/*.sh "$WORK"/scripts/*/*.sh "$WORK"/scripts/*/*/*.sh; do
    [ -f "$f" ] || continue
    sh -n "$f" 2>/dev/null || die "$(basename "$f") 语法检查失败，中止"
done
cp -rf "$WORK"/scripts/. "$CRASHDIR"/
chmod +x "$CRASHDIR"/*.sh "$CRASHDIR"/libs/*.sh "$CRASHDIR"/menus/*.sh "$CRASHDIR"/starts/*.sh 2>/dev/null
info "脚本已更新（整包覆盖，$(ls "$WORK"/scripts/*/*.sh 2>/dev/null | wc -l) 个子目录脚本）"

# 删掉 sing-box 专用脚本（本版只跑 concord）
_dropped=0
for f in $DROP; do
    if [ -f "$CRASHDIR/$f" ]; then
        rm -f "$CRASHDIR/$f" && _dropped=$((_dropped+1))
    fi
done
[ "$_dropped" -gt 0 ] && info "已删除 $_dropped 个 sing-box 专用脚本"

# ---------- 定时任务脚本 ----------
# task/task.sh 是 ShellCrash 安装时生成的副本，不从包里来，也不跟 scripts/ 一起更新。
# 但它才是 crontab 实际执行的那个文件（menus/task_cmd.sh 只是菜单用的同内容源），
# 不一起覆盖的话「自动更新内核」永远跑的是旧逻辑。
[ -f "$CRASHDIR/menus/task_cmd.sh" ] && {
    cp -f "$CRASHDIR/menus/task_cmd.sh" "$CRASHDIR/task/task.sh"
    chmod +x "$CRASHDIR/task/task.sh"
    info "同步 task/task.sh（定时任务实际执行的副本）"
}

# ---------- 配置 ----------
# 版本从 release 的 core-version asset 取。不能用 api.github.com——国内路由器实测超时，
# 拿不到就会写成 core_v=unknown，导致「自动更新内核」每天判定有新版本、白下一次 12MB。
VER="$(curl -fsSL --max-time 30 "$REL_BASE/core-version" 2>/dev/null | head -1 | tr -d '[:space:]')"
[ -z "$VER" ] && VER=unknown
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
    fetch "concord-$CONCORD_ARCH.gz" "$WORK/concord.gz" || die "下载内核失败"
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
