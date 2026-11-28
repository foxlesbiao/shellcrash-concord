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
warn() { echo "[警告] $*" >&2; }

# 别名写进 /etc/profile 只对登录 shell 生效。当前这个终端是安装脚本的父进程，
# 脚本改不了它的环境，所以 mm 会 not found —— 不提示的话用户只能重开 ssh 才发现。
alias_hint() {
    grep -q 'alias mm=' /etc/profile 2>/dev/null || return 0
    printf '\n' >&2
    printf '%s\n' "===========================================================||" >&2
    printf ' 别名已写入 /etc/profile，当前终端执行下面这行即可使用 mm：\n' >&2
    printf '\033[36m   . /etc/profile\033[0m\n' >&2
    printf '%s\n' " （或直接重开一个 ssh 会话）" >&2
    printf '%s\n' "===========================================================||" >&2
}

# ---------- 自动选源 ----------
# GitHub 直连在国内路由器上时通时不通（实测同一 URL 有时 5s、有时 60s 超时）。
# 脚本包和内核都在 release 里，镜像优先、直连兜底。

# 实测可用的镜像；ghfast 会按客户端 IP 长时间缓存 release 资产，不能只靠它
MIRRORS="https://gh-proxy.com/https://github.com
https://ghproxy.net/https://github.com
https://ghfast.top/https://github.com"

pick_sources() {
    info "探测下载源..."
    _ts=$(date +%s)
    _first=""
    for _m in $MIRRORS "https://github.com"; do
        _tag=$(curl -fsSL --max-time 10 "$_m/$REPO/releases/latest/download/core-version?t=$_ts" 2>/dev/null | head -1 | tr -d '[:space:]')
        if [ -n "$_tag" ]; then
            printf '  %-46s 可用（%s）\n' "$(echo "$_m" | sed 's|https://||')" "$_tag"
            [ -z "$_first" ] && { _first="$_m"; _first_tag="$_tag"; }
        else
            printf '  %-46s 不可用\n' "$(echo "$_m" | sed 's|https://||')"
        fi
    done
    [ -n "$_first" ] || die "下载源都不可用，检查网络"
    REL_BASE="$_first/$REPO/releases/download"
    TAG=$_first_tag
    info "下载源: $REL_BASE  版本: $TAG"
}

# 大文件下载：换源重试 + 时间戳破缓存。
# 用具体 tag 而不是 /latest/download（后者是重定向，镜像会缓存重定向目标）；
# 再加 ?t= 是因为实测同一个 tag 的同一个 URL，本机拿到新包、路由器拿到几代前的旧包。
fetch() { # $1=远程文件名  $2=本地路径
    _ts=$(date +%s)
    for _m in $MIRRORS "https://github.com"; do
        _url="$_m/$REPO/releases/download/$TAG/$1"
        curl -fsSL --retry 2 --retry-delay 2 --max-time 180 -o "$2" "$_url?t=$_ts" 2>/dev/null && return 0
        info " 下载失败，换源重试" >&2
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

# 列出能装 ShellCrash 的地方让用户挑。
# 同一块分区常被挂载十几次（小米固件把 ubi 挂到 /etc/* 下），按 Filesystem 去重；
# ramfs/tmpfs 重启就丢，装上去等于白装，直接排除。
pick_install_dir() {
    _cand=$(df -k 2>/dev/null | awk '
        NR == 1 { next }
        {
            fs = $1; avail = $4; mnt = $6
            if (seen[fs]++) next
            if (mnt ~ /^\/(rom|proc|sys|dev|tmp|var|run|overlay)(\/|$)/) next
            if (mnt ~ /^\/etc(\/|$)/) next
            if (fs ~ /^(tmpfs|ramfs|devtmpfs)$/) next
            if (avail < 40960) next
            printf "%s\t%d\t%s\n", mnt, avail, fs
        }')
    if [ -z "$_cand" ]; then
        # 有些 BusyBox 的 df 列数不一样，退回按挂载点去重
        _cand=$(df -k 2>/dev/null | awk 'NR > 1 && $4 > 40960 && $6 !~ /^\/(rom|proc|sys|dev|tmp|etc|var|run|overlay)/ && !seen[$6]++ {print $6"\t"$4"\t"$1}')
    fi
    [ -n "$_cand" ] || die "没有找到剩余空间 >40MB 的目录。插个 U 盘再来，或者手动指定：sh install.sh --bootstrap /mnt/xxx"

    printf '\n%s\n' "===========================================================||" >&2
    printf ' 选择安装位置（ShellCrash 约占 40MB）\n' >&2
    printf '%s\n' "===========================================================||" >&2
    _i=1
    _tab=$(printf '\t')
    while IFS="$_tab" read -r _m _a _f; do
        printf ' %d) %-28s 剩余 %s\n' "$_i" "$_m" "$(awk -v k="$_a" 'BEGIN{printf (k>=1048576)?"%.1fG":"%.0fM", (k>=1048576)?k/1048576:k/1024}')" >&2
        eval "_mnt_$_i=\$_m"
        _i=$((_i + 1))
    done <<EOF
$_cand
EOF
    _max=$((_i - 1))
    printf ' 0) 退出\n' >&2
    printf '%s\n' "===========================================================||" >&2
    while :; do
        printf '请输入对应数字> ' >&2
        read -r _sel || { printf '\n' >&2; return 1; }   # EOF（管道/非交互）就退出，别死循环
        [ "$_sel" = "0" ] && return 1
        case "$_sel" in
        ''|*[!0-9]*) printf ' 请输入数字\n' >&2; continue ;;
        esac
        [ "$_sel" -ge 1 ] && [ "$_sel" -le "$_max" ] && break
        printf ' 超出范围，1-%d\n' "$_max" >&2
    done
    eval "echo \"\$_mnt_$_sel\""
}

# 从零装到指定目录：直接用本仓库 release 里的 ShellCrash.tar.gz。
# 那本来就是"上游完整包 + 我们的全部改动"，上游安装脚本除了解包只多做两件事——
# 选别名、跑 init.sh（建 /etc/init.d 和 /etc/profile 别名），照做即可，
# 不需要先装一遍官方版再覆盖。
bootstrap_shellcrash() { # $1=安装目录（可为空，空则探测后让用户选）
    _dir="$1"
    [ -n "$_dir" ] || _dir=$(pick_install_dir) || exit 1
    # 用户可能填了带 /ShellCrash 的路径，去掉避免套两层
    _dir=$(echo "$_dir" | sed 's#/\+#/#g; s#/*$##; s#/ShellCrash$##')
    _cd="$_dir/ShellCrash"
    info "全新安装到 $_cd"
    mkdir -p "$_cd" || die "无法创建 $_cd"
    [ "$(df -k "$_dir" 2>/dev/null | awk 'NR==2{print $4}')" -gt 40960 ] 2>/dev/null \
        || die "$_dir 剩余空间不足 40MB"

    pick_sources
    _w=$(mktemp -d)
    fetch "ShellCrash.tar.gz" "$_w/p.tar.gz" || die "下载脚本包失败"
    tar -xzf "$_w/p.tar.gz" -C "$_cd" || die "解包失败"
    # $_w 留到 init.sh 跑完：失败时要读里面的 init.log

    # init.sh 靠这两个变量决定装到哪、别名叫什么。
    # 它会建 /etc/init.d/shellcrash、往 /etc/profile 写别名、把 my_alias 存进配置。
    # 别吞它的输出：失败时那个日志是唯一能看出哪一步炸了的东西。
    CRASHDIR="$_cd"; export CRASHDIR
    my_alias=mm; export my_alias
    # init.sh 第 84 行 setconfig versionsh_l $version，靠调用方提供这个变量。
    # 上游 install.sh 自己算，我们直接读包里那份，不然 set -u 当场报 parameter not set。
    version=$(cat "$_cd/version" 2>/dev/null || echo "1.0.0"); export version
    # 必须 set +eu：本脚本开着 set -eu，子 shell 会继承。
    #   -e：init.sh 里第一条返回非零的命令就把它整个打断，且没有任何输出。
    #   -u：setconfig 读 $3 这种可选参数直接报 "3: parameter not set"。
    # 上游的 init.sh 从来不是在 set -eu 下跑的，别让它继承我们的严格模式。
    ( set +eu; cd "$_cd" && . ./init.sh ) >"$_w/init.log" 2>&1 || true

    # 三个副作用逐个验，少一个都说明初始化没跑完
    _bad=""
    [ -f /etc/init.d/shellcrash ]          || _bad="$_bad /etc/init.d/shellcrash"
    grep -q 'alias mm=' /etc/profile 2>/dev/null || _bad="$_bad /etc/profile别名"
    grep -q '^my_alias=mm' "$_cd/configs/ShellCrash.cfg" 2>/dev/null || _bad="$_bad my_alias"
    if [ -n "$_bad" ]; then
        warn "初始化没跑完，缺:$_bad"
        warn "init.sh 输出："
        sed 's/^/    /' "$_w/init.log" | tail -12
        warn ""
        warn "补跑一次："
        warn "  CRASHDIR=$_cd my_alias=mm sh $_cd/init.sh"
        die "安装未完成"
    fi
    rm -rf "$_w"
    info "ShellCrash 已装好，别名 mm"
}

# --bootstrap <dir>：从零装；不带参数则按已有安装走
if [ "${1:-}" = "--bootstrap" ]; then
    bootstrap_shellcrash "${2:-}"
elif [ -z "${1:-}" ] || [ "${1#-}" = "$1" ]; then
    # 第一个参数不是 --bootstrap：可能是版本号，留给后面处理
    [ -z "${CRASHDIR:-}" ] && [ -z "$(find_crashdir || true)" ] && die "没找到 ShellCrash。全新路由器用：
  sh install.sh --bootstrap /mnt/sda1     （目录换成有空间的那个，会自动建）
已有 ShellCrash 的话直接 sh install.sh"
fi

CRASHDIR="${CRASHDIR:-$(find_crashdir || true)}"
[ -n "$CRASHDIR" ] || die "没找到 ShellCrash"
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
# 可选第一个参数指定版本：sh install.sh v0.1.0-r30
# 但 --bootstrap 已经自己选过源了，别把它当版本号
case "${1:-}" in
--bootstrap) REQ_TAG="" ;;
*)           REQ_TAG="${1:-}" ;;
esac
pick_sources
if [ -n "$REQ_TAG" ]; then
    case "$REQ_TAG" in
    v*|[0-9]*) info "指定版本: $REQ_TAG（跳过最新检查）"; TAG="$REQ_TAG" ;;
    *) die "版本号格式不对：$REQ_TAG（应形如 v0.1.0-r31）" ;;
    esac
fi
# 必须用探测选中的镜像，不能写死 github.com —— 路由器直连不通，
# 定时任务 update_core 会拿这个 URL 去下载，直连就永远失败。
CONCORD_RELEASE="${CONCORD_RELEASE:-$REL_BASE/$TAG/concord-$CONCORD_ARCH.gz}"

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

# 清理旧版残留的 sing-box 脚本。
# 包里本来就没有这些文件，但 cp 只覆盖不删除：从上游版或早期 fork 升级上来时，
# 它们会一直躺在 $CRASHDIR 里。core_exchange.sh 尤其危险——那是运行时把内核换回 mihomo 的东西。
_dropped=0
for f in $DROP; do
    if [ -f "$CRASHDIR/$f" ]; then
        rm -f "$CRASHDIR/$f" && _dropped=$((_dropped+1))
    fi
done
[ "$_dropped" -gt 0 ] && info "清理了 $_dropped 个旧版 sing-box 残留脚本"

# ---------- 定时任务脚本 ----------
# menus/task_cmd.sh 只是生成 task/task.sh 的原料，init.sh 本来就用 mv 把它搬走
# （见上游 init.sh：mv -f menus/task_cmd.sh task/task.sh）。刚才的 cp -rf 又把它
# 复制回来了，这里必须照原样 mv 一次，否则 menus/ 下永远多一份副本，
# 而且 crontab 实际执行的 task/task.sh 还是旧版——「自动更新内核」跑的是旧逻辑。
if [ -f "$CRASHDIR/menus/task_cmd.sh" ]; then
    mkdir -p "$CRASHDIR/task"
    mv -f "$CRASHDIR/menus/task_cmd.sh" "$CRASHDIR/task/task.sh"
    chmod +x "$CRASHDIR/task/task.sh"
    info "task/task.sh 已更新（crontab 实际执行的那份）"
fi

# ---------- 配置 ----------
# 版本从 release 的 core-version asset 取。不能用 api.github.com——国内路由器实测超时，
# 拿不到就会写成 core_v=unknown，导致「自动更新内核」每天判定有新版本、白下一次 12MB。
VER="$TAG"
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
# 内核在 $CRASHDIR/CrashCore.raw；$CRASHDIR/CrashCore 是 $TMPDIR 下的软链，这里不存在。
# 原来判断的就是那个不存在的路径，于是每次安装都判定"没装内核"、重下 12MB。
if [ -f "$CRASHDIR/CrashCore.raw" ] && "$CRASHDIR/CrashCore.raw" run -h 2>&1 | grep -qi concord; then
    info "内核已是 concord，跳过下载"
else
    info "下载 concord 内核"
    fetch "concord-$CONCORD_ARCH.gz" "$WORK/concord.gz" || die "下载内核失败"
    gzip -dc "$WORK/concord.gz" > "$WORK/concord" || die "解压内核失败"
    chmod +x "$WORK/concord"
    "$WORK/concord" run -h 2>&1 | grep -qi concord || die "下载到的不是 concord 内核"
    cp -f "$WORK/concord" "$CRASHDIR/CrashCore.raw"
    chmod +x "$CRASHDIR/CrashCore.raw"
    info "内核已更新: $(ls -lh "$CRASHDIR/CrashCore.raw" | awk '{print $5}')"
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
    alias_hint
else
    # 全新装好的 ShellCrash 还没有订阅，也就没有配置文件，内核本来起不来。
    # 这是预期状态，不是安装失败。
    if [ ! -s "$CRASHDIR/configs/providers.cfg" ] && [ ! -s "$CRASHDIR/yamls/config.yaml" ]; then
        info "concord 已就位，但还没有订阅"
        info ""
        info "下一步："
        info "  1) 敲 mm 进菜单"
        info "  2) 6) 配置文件管理 → 导入订阅链接"
        info "  3) 选好节点后服务会自动启动"
        alias_hint
        rm -rf "$WORK"
        exit 0
    fi
    info "内核未启动，查看 $CRASHDIR/ShellCrash.log"
    tail -5 "$CRASHDIR/ShellCrash.log" 2>/dev/null | sed 's/^/  /'
    alias_hint
    rm -rf "$WORK"
    exit 1
fi

rm -rf "$WORK"
