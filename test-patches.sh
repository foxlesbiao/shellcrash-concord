#!/bin/sh
# shellcrash-concord 补丁逻辑测试
#
# 只测本仓库对 ShellCrash 的改动是否正确，不碰网络、不碰节点、不碰真实配置。
# 所有外部依赖（setconfig/webget/logger/pidof/二进制）都是 mock。
#
# 用法: sh test-patches.sh
# 退出码 = 失败数

SRC="${SRC:-$(dirname "$0")/ShellCrash/scripts}"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
no()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [ -n "$2" ] && printf '        期望: %s\n        实际: %s\n' "$3" "$2"; }
eq()  { [ "$2" = "$3" ] && ok "$1" || no "$1" "$2" "$3"; }
has() { echo "$2" | grep -q "$3" && ok "$1" || no "$1" "$2" "包含 $3"; }
hasnt(){ echo "$2" | grep -q "$3" && no "$1" "$2" "不含 $3" || ok "$1"; }
sec() { printf '\n\033[36m== %s ==\033[0m\n' "$1"; }

# ---------- 沙盒 ----------
# 本脚本会改写 TMPDIR，先钉死一个干净的父目录（避免被外部环境污染）
unset TMPDIR
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/scc-test.XXXXXX" 2>/dev/null || mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

CRASHDIR="$SANDBOX/crash"; BINDIR="$CRASHDIR"; TMPDIR="$SANDBOX/tmp"
for d in configs libs starts menus ui; do mkdir -p "$CRASHDIR/$d"; done
mkdir -p "$TMPDIR" "$SANDBOX/configs"
: > "$SANDBOX/configs/ShellCrash.cfg"
# web_get_bin.sh 第一行会 source 这个，给个空壳免得中途退出
: > "$CRASHDIR/libs/web_get.sh"
export CRASHDIR BINDIR TMPDIR

# mock：setconfig 照抄真实实现（写真实文件，供后续 . 加载），同时记一份日志
setconfig() {
    _cp="${3:-$SANDBOX/configs/ShellCrash.cfg}"
    sed -i "/^${1}=.*/d" "$_cp" 2>/dev/null
    printf '%s=%s\n' "$1" "$2" >> "$_cp"
    printf '%s=%s\n' "$1" "$2" >> "$SANDBOX/cfg.log"
}
webget()    { echo "$2"; }
logger()    { echo "LOG[$2] $1" >> "$SANDBOX/logger.log"; }
pidof()     { return 1; }
store_raw_worth_it() { return 0; }

# 每次测试前清空 mock 记录
reset() {
    : > "$SANDBOX/cfg.log"; : > "$SANDBOX/logger.log"
    rm -f "$SANDBOX/configs/ShellCrash.cfg" "$CRASHDIR/configs/command.env"
}

# 造一个假内核二进制：$1=行为(concord|mihomo|singbox)
fake_core() {
    f="$SANDBOX/core_new"
    case "$1" in
    concord) printf '#!/bin/sh\ncase "$1" in run) echo "concord $*";; esac\n' > "$f" ;;
    mihomo)  printf '#!/bin/sh\ncase "$1" in -h) echo "mihomo -t -d -f";; -v) echo "v1.19.17 linux amd64";; esac\n' > "$f" ;;
    singbox) printf '#!/bin/sh\ncase "$1" in -h) echo "sing-box run -D -C";; version) echo "sing-box version 1.10.0";; esac\n' > "$f" ;;
    esac
    chmod +x "$f"
}

# ---------- 1. core_check：内核识别 ----------
sec "1. core_check() 内核识别"

. "$SRC/libs/core_tools.sh" 2>/dev/null

# concord
reset; fake_core concord
cp "$SANDBOX/core_new" "$SANDBOX/test-bin"; crashcore=concord
core_check "$SANDBOX/test-bin"
has "concord 识别 -> COMMAND 用 run -c" "$COMMAND" 'run -c'
hasnt "concord 不用 mihomo 的 -f 参数" "$COMMAND" ' -f '
N=$(ls "$BINDIR" 2>/dev/null | grep -cE '^CrashCore\.(raw|gz|upx|tar\.gz)$')
eq  "concord 内核已落盘（raw/gz/upx 之一）" "$N" "1"
grep -q 'CrashCore run -c' "$CRASHDIR/configs/command.env" 2>/dev/null \
    && ok "command.env 已写入 concord 启动命令" || no "command.env 未写入 concord 启动命令" \
    "$(cat "$CRASHDIR/configs/command.env" 2>/dev/null)"

# mihomo（回归：不能把普通内核误判成 concord）
reset; fake_core mihomo
cp "$SANDBOX/core_new" "$SANDBOX/test-bin"; crashcore=meta; rm -f "$BINDIR"/CrashCore.*
core_check "$SANDBOX/test-bin"
has "mihomo 识别 -> COMMAND 用 -d/-f" "$COMMAND" '\-d .* -f '
hasnt "mihomo 不会被当成 concord" "$COMMAND" 'run -c'

# singbox（已不支持：识别不出来就该拒绝，不能悄悄当成 mihomo 启动）
reset; fake_core singbox
cp "$SANDBOX/core_new" "$SANDBOX/test-bin"; crashcore=singboxr; rm -f "$BINDIR"/CrashCore.*
core_check "$SANDBOX/test-bin"
hasnt "singbox 二进制不会生成 run -D 命令" "$COMMAND" 'run -D'
hasnt "singbox 二进制不会生成 run -c 命令" "$COMMAND" 'run -c'

# ---------- 2. core_find：选对内核文件 ----------
sec "2. core_find() 选文件"

rm -rf "$TMPDIR"/CrashCore "$TMPDIR"/CrashCore.* "$BINDIR"/CrashCore.*
# 注意：core_tools.sh 里 find_para = '-size +2000'，GNU find 的单位是 512 字节块，
# 也就是约 1MB 阈值。测试文件必须超过 1MB 才会被 find 看到。
head -c 2000000 /dev/zero | tr '\0' 'r' > "$BINDIR/CrashCore.raw"
head -c 2000000 /dev/zero | tr '\0' 'o' > "$BINDIR/CrashCore.raw.mihomo.bak"
head -c 2000000 /dev/zero | tr '\0' 'e' > "$BINDIR/CrashCore.raw.concord"
core_find
LINK=$(readlink "$TMPDIR/CrashCore" 2>/dev/null)
eq  "选中 CrashCore.raw，不选 .bak" "$LINK" "$BINDIR/CrashCore.raw"

# 只有 .bak 时不该选它
rm -f "$TMPDIR"/CrashCore "$TMPDIR"/CrashCore.* "$BINDIR"/CrashCore.raw "$BINDIR"/CrashCore.raw.concord
core_find
LINK=$(readlink "$TMPDIR/CrashCore" 2>/dev/null)
eq  "只有备份时不加载" "$LINK" ""

# ---------- 3. get_bin：更新源 URL ----------
sec "3. get_bin() 更新源 URL"

. "$SRC/libs/web_get_bin.sh" 2>/dev/null

reset; crashcore=concord; custcorelink=''; url_id=101; release_type=master
U=$(get_bin "$TMPDIR/x" version)
has "concord: version 走 release 镜像" "$U" 'ghfast.top/.*/releases/latest/download/version'
hasnt "concord: 忽略 url_id=101 的上游地址" "$U" 'juewuy'

reset; crashcore=concord; custcorelink=''; url_id=101
U=$(get_bin "$TMPDIR/x" ShellCrash.tar.gz)
has "concord: 脚本包走 release" "$U" 'releases/latest/download/ShellCrash.tar.gz'

reset; crashcore=concord; custcorelink=''; url_id=101
U=$(get_bin "$TMPDIR/x" bin/geodata/cn_mini.mmdb)
has "concord: geo 数据走 jsDelivr" "$U" 'jsdelivr.*shellcrash-concord@main'
has "concord: geo 路径映射到 ShellCrash/ 子目录" "$U" 'ShellCrash/bin/geodata'

reset; crashcore=meta; custcorelink=''; url_id=''
U=$(get_bin "$TMPDIR/x" version)
hasnt "非 concord: 仍走上游（不被本仓库劫持）" "$U" 'shellcrash-concord'
has  "非 concord: 用上游地址" "$U" 'juewuy/ShellCrash'

# 通过 custcorelink 也能识别 concord（首次装、配置还没写全时）
reset; crashcore=meta; custcorelink='https://x/concord-aarch64.gz'; url_id=101
U=$(get_bin "$TMPDIR/x" version)
has "custcorelink 含 concord 也能识别" "$U" 'shellcrash-concord'

# ---------- 4. menu.sh 面板地址 ----------
sec "4. 面板地址 hostdir"

hostdir_of() {
    crashcore="$1"; CRASHDIR="$SANDBOX/crash"; db_port=9999
    if [ -f /www/clash/index.html ]; then hostdir=/clash
    elif echo "$crashcore" | grep -qi 'concord'; then hostdir=":8090"
    else hostdir=":$db_port/ui"; fi
    echo "$hostdir"
}
eq "concord -> :8090"          "$(hostdir_of concord)" ":8090"
eq "meta -> :9999/ui"          "$(hostdir_of meta)"    ":9999/ui"
eq "singboxr -> :9999/ui"      "$(hostdir_of singboxr)" ":9999/ui"

# 真文件里的分支也要在（防止改回硬编码）
grep -q "concord' \]; then" "$SRC/menu.sh" 2>/dev/null || grep -q "grep -qi 'concord'" "$SRC/menu.sh" \
    && ok "menu.sh 里有 concord 分支" || no "menu.sh 里没有 concord 分支"

# ---------- 5. clash_check：不被换回 mihomo ----------
sec "5. clash_check() 不换内核"

core_exchange() { echo "EXCHANGED:$1" >> "$SANDBOX/exchange.log"; }
CFG="$SANDBOX/cfg"
printf 'crashcore=concord\n' > "$CFG"
crashcore=concord
core_config="$SANDBOX/core.yaml"
printf -- '- {name: n1, type: vless, server: x, port: 443, uuid: y}\n' > "$core_config"
redir_mod=Mix

reset; : > "$SANDBOX/exchange.log"
# 只测 vless 检测这一段逻辑
if ! echo "$crashcore" | grep -qi 'concord'; then
    [ "$crashcore" != "meta" ] && [ -n "$(cat $core_config | grep -oE 'type: vless|type: hysteria')" ] \
        && core_exchange meta 'vless/hy协议'
fi
eq "concord + vless 不触发换内核" "$(cat "$SANDBOX/exchange.log" 2>/dev/null)" ""

# 对照：非 concord 时应该触发
crashcore=clash
: > "$SANDBOX/exchange.log"
if ! echo "$crashcore" | grep -qi 'concord'; then
    [ "$crashcore" != "meta" ] && [ -n "$(cat $core_config | grep -oE 'type: vless|type: hysteria')" ] \
        && core_exchange meta 'vless/hy协议'
fi
has "非 concord + vless 会触发换内核（原行为保留）" "$(cat "$SANDBOX/exchange.log" 2>/dev/null)" 'EXCHANGED:meta'

# ---------- 6. init.sh 生成 command.env ----------
sec "6. init.sh command.env"

gen_command() {
    CFG_PATH="$1"
    if [ -n "$(grep 'crashcore=concord' "$CFG_PATH")" ]; then
        COMMAND='"$TMPDIR/CrashCore run -c $TMPDIR/config.yaml -d $TMPDIR/concord-home"'
    else
        COMMAND='"$TMPDIR/CrashCore -d $BINDIR -f $TMPDIR/config.yaml"'
    fi
    echo "$COMMAND"
}
eq "concord -> run -c"       "$(gen_command "$CFG")"  '"$TMPDIR/CrashCore run -c $TMPDIR/config.yaml -d $TMPDIR/concord-home"'
printf 'crashcore=singboxr\n' > "$SANDBOX/cfg2"
eq "singbox -> 回落"         "$(gen_command "$SANDBOX/cfg2")" '"$TMPDIR/CrashCore -d $BINDIR -f $TMPDIR/config.yaml"'
printf 'crashcore=meta\n' > "$SANDBOX/cfg3"
eq "meta -> -d/-f"           "$(gen_command "$SANDBOX/cfg3")" '"$TMPDIR/CrashCore -d $BINDIR -f $TMPDIR/config.yaml"'

# 真实 init.sh 里要有这个分支
grep -q "crashcore=concord" "$SRC/init.sh" && ok "init.sh 里有 concord 分支" || no "init.sh 里没有 concord 分支"

# ---------- 6.5 tun stack ----------
sec "6.5 tun stack 兼容性"

# 上游 master 写 stack: mips，mihomo v1.19.x 报 invalid tun stack（实测）。
# 必须是 system，否则回滚到 mihomo 直接起不来。
if grep -q 'stack: system' "$SRC/starts/clash_modify.sh"; then
    ok "clash_modify.sh 用 stack: system（mihomo 全版本兼容）"
else
    no "clash_modify.sh 仍写 stack: mips" "$(grep -o 'stack: [a-z]*' "$SRC/starts/clash_modify.sh" | head -1)" "stack: system"
fi
# 只看实际的赋值行，注释里提到 mips 是正常的
grep -E '^[[:space:]]*tun=' "$SRC/starts/clash_modify.sh" | grep -q 'stack: mips' \
    && no "代码里还残留 stack: mips" || ok "无 mips 残留（注释除外）"

# 回滚功能已移除（纯 concord 不留 mihomo 退路）
I="$(dirname "$0")/install.sh"
grep -q 'rollback' "$I" 2>/dev/null && no "install.sh 仍含回滚逻辑" || ok "install.sh 无回滚逻辑"
# 只看实际命令（注释里提到 mihomo.bak 是解释性的）
grep -E '^[[:space:]]*[^#].*mihomo\.bak' "$I" 2>/dev/null | grep -q . \
    && no "install.sh 仍备份 mihomo" || ok "install.sh 不备份 mihomo"

# ---------- 7. test_yaml：校验命令 ----------
sec "7. test_yaml() 校验命令"

# concord 用 -t -c，mihomo 用 -t -d -f。检查代码里两条路径都在。
grep -q '\-t -c .*config.yaml' "$SRC/starts/clash_modify.sh" && ok "concord 校验用 -t -c" || no "缺少 -t -c 分支"
grep -q '\-t -d .* -f ' "$SRC/starts/clash_modify.sh" && ok "mihomo 校验仍用 -t -d -f" || no "mihomo 校验分支丢失"
grep -q "run -h 2>&1 | grep -qi 'concord'" "$SRC/starts/clash_modify.sh" "$SRC/libs/core_tools.sh" 2>/dev/null \
    && ok "按二进制能力判定（run -h 探测）" || no "未按二进制能力判定"

# ---------- 8. 归一化：concord 复用 meta 配置生成 ----------
sec "8. crashcore 归一化"

grep -q 'core_kind="\$crashcore"' "$SRC/starts/clash_modify.sh" && ok "保留原始内核类型到 core_kind" || no "缺少 core_kind 保存"
grep -q "concord' \]; then crashcore=meta\|concord.*&& crashcore=meta\|grep -qi 'concord' && crashcore=meta" "$SRC/starts/clash_modify.sh" \
    && ok "concord 归一化为 meta" || no "缺少归一化"

# listeners 生成逻辑已整块移除（meta_listeners.sh 也删了）
grep -q 'meta_listeners' "$SRC/starts/clash_modify.sh" \
    && no "clash_modify 仍引用 meta_listeners" || ok "listeners 生成逻辑已移除"

# ---------- 9. 菜单裁剪 ----------
sec "9. 菜单裁剪"

hasnt "7_gateway 无 VMess 入站"  "$(cat "$SRC/menus/7_gateway.sh")" 'set_vmess'
hasnt "7_gateway 无 SS 入站"     "$(cat "$SRC/menus/7_gateway.sh")" 'set_shadowsocks'
hasnt "7_gateway 无 Tailscale（concord 不支持）" "$(cat "$SRC/menus/7_gateway.sh")" 'set_tailscale'
has  "7_gateway 保留 WireGuard"  "$(cat "$SRC/menus/7_gateway.sh")" 'set_wireguard'

has  "内核菜单只留 Concord"      "$(cat "$SRC/menus/9_upgrade.sh")" '更新 Concord 内核'
hasnt "内核菜单无 mihomo 源"     "$(cat "$SRC/menus/9_upgrade.sh")" 'MetaCubeX/mihomo'
hasnt "自定义内核无 sing-box 源" "$(cat "$SRC/menus/9_upgrade.sh")" 'SagerNet/sing-box'
hasnt "已删切换内核：无自定义源函数" "$(cat "$SRC/menus/9_upgrade.sh")" 'setcustcore'
hasnt "已删切换内核：无 checkcustcore" "$(cat "$SRC/menus/9_upgrade.sh")" 'checkcustcore'
hasnt "已删切换内核：无 setziptype"    "$(cat "$SRC/menus/9_upgrade.sh")" 'setziptype'
hasnt "已删切换内核：菜单无自定义链接" "$(cat "$SRC/menus/9_upgrade.sh")" '自定义内核链接'
has  "setcoretype 无交互直接设 concord" "$(sed -n '/^setcoretype()/,/^}/p' "$SRC/menus/9_upgrade.sh")" 'crashcore=concord'
hasnt "setcoretype 不再弹选择菜单"      "$(sed -n '/^setcoretype()/,/^}/p' "$SRC/menus/9_upgrade.sh")" 'btm_box'

has  "geo 菜单按内核过滤"        "$(cat "$SRC/menus/9_upgrade.sh")" 'concord.*只读\|concord.*mrs\|geo_pat'
has  "PAC 对 concord 有提示"     "$(cat "$SRC/menus/9_upgrade.sh")" 'concord 没有 PAC'

# 多架构：按 cpucore 选对应内核
has  "菜单按架构选内核 (arm64)"   "$(cat "$SRC/menus/9_upgrade.sh")" "arm64).*aarch64_generic"
has  "菜单按架构选内核 (amd64)"   "$(cat "$SRC/menus/9_upgrade.sh")" "amd64).*x86_64"
has  "不支持架构时有提示"         "$(cat "$SRC/menus/9_upgrade.sh")" '当前架构.*暂无 concord'
hasnt "内核 URL 不再硬编码 aarch64" "$(cat "$SRC/menus/9_upgrade.sh")" 'download/concord-aarch64.gz'

# 切换安装源已删（concord 下 update_url 被钉死，改了无效）
hasnt "已删切换安装源菜单"        "$(cat "$SRC/menus/9_upgrade.sh")" 'UPG_MENU_SOURCE'
hasnt "已删 setserver 调用"       "$(cat "$SRC/menus/providers_clash.sh")" 'setserver'
# providers_singbox.sh 整个文件已删除，无需再检查其内容

# ---------- 10. 补丁与上游一致性 ----------
sec "10. 补丁文件"

PATCH="$(dirname "$0")/patches/shellcrash-concord.patch"
[ -f "$PATCH" ] && ok "补丁文件存在" || no "补丁文件缺失"
N=$(grep -c '^diff --git' "$PATCH" 2>/dev/null)
[ "${N:-0}" -ge 40 ] && ok "补丁覆盖 $N 个文件（含删除）" || no "补丁只覆盖 ${N:-0} 个文件（预期 >=40）"

# 三个关键补丁标记
for f in init.sh libs/core_tools.sh libs/web_get_bin.sh; do
    grep -q "$f" "$PATCH" 2>/dev/null && ok "补丁含 $f" || no "补丁缺 $f"
done

# ---------- 11. 纯 concord：sing-box 专用文件已移除 ----------
sec "11. 纯 concord 完整性"

SDIR="$(dirname "$0")/ShellCrash/scripts"
for f in starts/singbox_modify.sh starts/singbox_check.sh starts/singbox_config_check.sh \
         menus/providers_singbox.sh libs/meta_listeners.sh starts/core_exchange.sh; do
    [ -f "$SDIR/$f" ] && no "仍存在 $f" || ok "已删除 $f"
done

# core_exchange 是"换内核"的核心，删了才叫纯 concord
DANG=$(grep -rn 'core_exchange' "$SDIR" 2>/dev/null | grep -v '^.*#' | wc -l)
[ "$DANG" -eq 0 ] && ok "无 core_exchange 调用（不换内核）" || no "$DANG 处仍在调 core_exchange"

# 补丁里应体现为删除
grep -q 'deleted file mode' "$PATCH" && ok "补丁含文件删除记录" || no "补丁没有删除记录"

# 不能有指向已删文件的 source
DANGLING=$(grep -rn 'singbox_modify\|singbox_check\|singbox_config_check\|providers_singbox\|meta_listeners' "$SDIR" 2>/dev/null | wc -l)
[ "$DANGLING" -eq 0 ] && ok "无指向已删文件的引用" || no "$DANGLING 处 dangling 引用"

# 面板包只留 zashboard
DBDIR="$(dirname "$0")/ShellCrash/bin/dashboard"
[ -f "$DBDIR/zashboard.tar.gz" ] && ok "保留 zashboard" || no "zashboard 丢了"
# 注意：grep -vc 无匹配时 exit=1，别用 || echo 0（会输出两行把 -eq 搞崩）
DB_OTHER=$(ls "$DBDIR" 2>/dev/null | grep -v zashboard | wc -l | tr -d ' ')
[ "${DB_OTHER:-0}" -eq 0 ] && ok "无其他面板包" || no "还有 ${DB_OTHER} 个非 zashboard 面板"

# bin 里不该再有 mihomo/sing-box
[ -d "$(dirname "$0")/ShellCrash/bin/meta" ] && no "bin/meta 仍在" || ok "bin/meta 已删"
[ -d "$(dirname "$0")/ShellCrash/bin/singboxr" ] && no "bin/singboxr 仍在" || ok "bin/singboxr 已删"

# workflow 改成每日
grep -q 'cron: "0 4 \* \* \*"' "$(dirname "$0")/.github/workflows/sync.yml" \
    && ok "内核同步为每日" || no "内核同步不是每日"

# ---------- 汇总 ----------
printf '\n\033[36m== 汇总 ==\033[0m\n'
printf '  PASS %s   FAIL %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && printf '\033[32m补丁逻辑测试全部通过\033[0m\n' || printf '\033[31m%s 项失败\033[0m\n' "$FAIL"
exit "$FAIL"
