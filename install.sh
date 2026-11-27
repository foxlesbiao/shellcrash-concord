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
CONCORD_RELEASE="${CONCORD_RELEASE:-https://github.com/foxlesbiao/shellcrash-concord/releases/latest/download/concord-aarch64.gz}"

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
    for f in core_tools.sh clash_modify.sh 9_upgrade.sh; do
        [ -f "$CRASHDIR/.orig/$f.orig" ] && cp -f "$CRASHDIR/.orig/$f.orig" \
            "$(find "$CRASHDIR" -name "$f" -not -path "*/.orig/*" | head -1)"
    done
    set_cfg crashcore    meta
    set_cfg custcorelink ""
    sh "$CRASHDIR/start.sh" restart
    exit 0
fi

# ---------- 备份 ----------
if [ ! -f "$CRASHDIR/CrashCore.raw.mihomo.bak" ]; then
    info "备份原始脚本与内核"
    { [ -f "$CRASHDIR/CrashCore.raw" ] && cp -f "$CRASHDIR/CrashCore.raw" "$CRASHDIR/CrashCore.raw.mihomo.bak"; } || true
    mkdir -p "$CRASHDIR/.orig"
    for f in libs/core_tools.sh starts/clash_modify.sh menus/9_upgrade.sh; do
        [ -f "$CRASHDIR/$f" ] && cp -f "$CRASHDIR/$f" "$CRASHDIR/.orig/$(basename "$f").orig"
    done
fi

# ---------- 拉取改过的脚本 ----------
WORK="/tmp/scc.$$"; mkdir -p "$WORK"
info "下载 shellcrash-concord 补丁文件"
for f in libs/core_tools.sh starts/clash_modify.sh menus/9_upgrade.sh; do
    url="https://raw.githubusercontent.com/$REPO/$BRANCH/ShellCrash/scripts/$f"
    curl -fsSL --retry 3 --max-time 60 -o "$WORK/$(basename "$f")" "$url" || die "下载 $f 失败"
    sh -n "$WORK/$(basename "$f")" || die "$f 语法检查失败，中止"
    cp -f "$WORK/$(basename "$f")" "$CRASHDIR/$f"
done
info "补丁已应用"

# ---------- 配置 ----------
VER="$(basename "$CONCORD_RELEASE" | sed -n 's/^concord-aarch64.*//p')"
VER="${VER:-0.1.0}"
set_cfg crashcore    concord
set_cfg concord_v    "$VER"
set_cfg custcorelink "$CONCORD_RELEASE"
info "配置: crashcore=concord custcorelink=$CONCORD_RELEASE"

# ---------- 内核 ----------
mkdir -p "$CRASHDIR/concord"
if ! "$CRASHDIR/CrashCore" run -h 2>&1 | grep -qi concord; then
    info "下载 concord 内核"
    curl -fsSL --retry 3 --max-time 300 -o "$WORK/concord.gz" "$CONCORD_RELEASE" || die "下载内核失败"
    gzip -dc "$WORK/concord.gz" > "$WORK/concord"; chmod +x "$WORK/concord"
    cp -f "$WORK/concord" "$CRASHDIR/CrashCore.raw"
fi

info "重启 ShellCrash"
sh "$CRASHDIR/start.sh" restart >/dev/null 2>&1 || true
sleep 12

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
