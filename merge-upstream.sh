#!/bin/sh
# 手动合并上游 ShellCrash。
#
# 不自动提交、不自动推送：这里只把上游拉下来、试打补丁、把结果摆好，
# 冲突时停下来给你看清楚再决定。合并完自己 commit。
#
# 用法:
#   sh merge-upstream.sh           # 试合并，改动写进工作区
#   sh merge-upstream.sh --check   # 只看能不能打，不动任何文件
#
# 上游地址可用 UPSTREAM= 覆盖，默认 juewuy/ShellCrash。
set -e
REPO=$(cd "$(dirname "$0")" && pwd)
UPSTREAM=${UPSTREAM:-https://github.com/juewuy/ShellCrash.git}
CHECK=0
[ "$1" = "--check" ] && CHECK=1

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

echo "== 拉上游 =="
if ! git clone --depth 1 "$UPSTREAM" "$W/up" 2>&1 | tail -1; then
    echo "拉取失败。国内网络下 github.com 常不通，试:"
    echo "  UPSTREAM=https://ghfast.top/https://github.com/juewuy/ShellCrash.git sh $0"
    exit 1
fi
UPREV=$(git -C "$W/up" rev-parse --short HEAD)
echo "  上游 $UPREV  $(git -C "$W/up" log -1 --format='%s' | cut -c1-60)"
echo "  本地 $(cat "$REPO/ShellCrash/.upstream-revision" 2>/dev/null | cut -c1-7 || echo 未知)"

echo "== 试打补丁 =="
cd "$W/up"
if ! patch -p1 --batch --forward --dry-run < "$REPO/patches/shellcrash-concord.patch" > "$W/probe.log" 2>&1; then
    echo "补丁打不上，上游改了我们改过的地方："
    echo
    grep -E 'Hunk #[0-9]+ FAILED|Reversed|can.t find file' "$W/probe.log" | sed 's/^/  /' || cat "$W/probe.log" | sed 's/^/  /'
    echo
    echo "别硬来。按下面顺序处理："
    echo "  1. 看是哪个文件的哪个 hunk 冲突（上面列出的）"
    echo "  2. 手动把上游的改动并进 ShellCrash/ 对应文件"
    echo "  3. 跑 sh test-patches.sh 确认没漏东西"
    echo "  4. 重跑 sh regen-patch.sh 重新生成补丁"
    echo
    echo "补丁概览（改过哪些文件）："
    grep '^diff --git' "$REPO/patches/shellcrash-concord.patch" | sed 's|diff --git a/||; s| b/.*||' | sed 's/^/  /'
    exit 1
fi
echo "  可打"

[ "$CHECK" = 1 ] && { echo; echo "--check 模式，未改动任何文件"; exit 0; }

echo "== 应用补丁 + 同步 =="
cd "$W/up"
patch -p1 --batch --forward < "$REPO/patches/shellcrash-concord.patch" >/dev/null

# scripts/ 和 tools/ 都要同步：补丁改过 tools/tg_bot.sh
rsync -a --delete "$W/up/scripts/" "$REPO/ShellCrash/scripts/"
rsync -a --delete "$W/up/tools/"   "$REPO/ShellCrash/tools/"

# bin/rules/public 里的 mihomo/sing-box 包同步回来后要再删一次，
# 上游会重新提交它们（rsync 只覆盖 scripts/tools，这里只是防御）
rm -rf "$REPO/ShellCrash/bin/meta" "$REPO/ShellCrash/bin/singboxp" "$REPO/ShellCrash/bin/singboxr" \
       "$REPO/ShellCrash/bin/clashfm.tar.gz" "$REPO/ShellCrash/rules/singbox_providers" 2>/dev/null || true

git -C "$W/up" rev-parse HEAD > "$REPO/ShellCrash/.upstream-revision"
git -C "$W/up" log -1 --format='%h %s'  > "$REPO/ShellCrash/.upstream-summary"

echo "== 自检 =="
cd "$REPO"
env -u TMPDIR sh test-patches.sh 2>&1 | tail -2

echo
echo "== 改动 =="
git status --short | head -20
echo
echo "确认没问题再提交："
echo "  cd $REPO && git add -A && git commit -m 'chore: sync upstream $UPREV'"
