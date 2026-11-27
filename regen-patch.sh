#!/bin/sh
# 从上游生成补丁：不手工维护文件清单，直接 diff 整个 scripts/ 和 tools/。
# 手工 FILES 列表漏过文件（start.sh、lang/en/providers.lang），导致 sync 时改动被覆盖。
#
# 用法: sh regen-patch.sh [上游路径]
set -e
UP=${1:-/home/hermes/.hermes/cache/scratch/ShellCrash-src}
REPO=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/a" "$WORK/b"
cp -r "$UP/scripts" "$WORK/a/scripts"
cp -r "$UP/tools"   "$WORK/a/tools" 2>/dev/null || mkdir -p "$WORK/a/tools"
cp -r "$REPO/ShellCrash/scripts" "$WORK/b/scripts"
cp -r "$REPO/ShellCrash/tools"   "$WORK/b/tools" 2>/dev/null || mkdir -p "$WORK/b/tools"

cd "$WORK"
git diff --no-index --no-color a b 2>/dev/null |
    sed 's|^diff --git a/a/|diff --git a/|; s| b/b/| b/|; s|^--- a/a/|--- a/|; s|^+++ b/b/|+++ b/|' \
    > "$REPO/patches/shellcrash-concord.patch" || true

echo "补丁: $(grep -c '^diff --git' "$REPO/patches/shellcrash-concord.patch") 文件 / $(wc -l < "$REPO/patches/shellcrash-concord.patch") 行 / $(grep -c 'deleted file mode' "$REPO/patches/shellcrash-concord.patch") 删除"

# 自检：干净上游 --dry-run 必须全过
T=$(mktemp -d)
trap 'rm -rf "$WORK" "$T"' EXIT
cp -r "$UP/scripts" "$T/scripts"
cp -r "$UP/tools"   "$T/tools" 2>/dev/null || mkdir -p "$T/tools"
cd "$T" && patch -p1 --batch --forward --dry-run < "$REPO/patches/shellcrash-concord.patch" >/dev/null 2>&1 \
    && echo "dry-run: OK" || { echo "dry-run: FAILED"; exit 1; }

# 再打一遍并比对，确认打完 == 仓库（这才是 sync 的正确性）
cd "$T" && patch -p1 --batch --forward < "$REPO/patches/shellcrash-concord.patch" >/dev/null 2>&1
D=$(diff -rq "$T/scripts" "$REPO/ShellCrash/scripts" 2>/dev/null | wc -l)
[ "$D" = "0" ] && echo "一致性: OK（补丁打完后与仓库完全一致）" || { echo "一致性: $D 个文件不一致"; diff -rq "$T/scripts" "$REPO/ShellCrash/scripts" | head; exit 1; }
