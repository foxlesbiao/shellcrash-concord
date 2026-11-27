. "$CRASHDIR"/libs/web_get.sh

get_bin() { #专用于项目内部文件的下载
    # concord 版：脚本/数据一律从本仓库取，忽略 url_id 指向的上游服务器列表
    if echo "$crashcore$custcorelink" | grep -qi 'concord'; then
        update_url="${concord_update_url:-https://testingcf.jsdelivr.net/gh/foxlesbiao/shellcrash-concord@main}"
        url_id=''
    fi
    [ -z "$update_url" ] && update_url=https://testingcf.jsdelivr.net/gh/juewuy/ShellCrash@master
    if [ -n "$url_id" ]; then
        [ -n "$release_type" ] && rt="$release_type" || rt=master
        echo "$2" | grep -q '^bin/' && rt=update #/bin文件改为在update分支下载
        echo "$2" | grep -qE '^public/|^rules/' && rt=dev #/public和/rules文件改为在dev分支下载    
        if [ "$url_id" = 101 -o "$url_id" = 104 ]; then
            bin_url="$(grep "$url_id" "$CRASHDIR"/configs/servers_chs.list | awk '{print $3}')@$rt/$2" #jsdelivr特殊处理
        else
            bin_url="$(grep "$url_id" "$CRASHDIR"/configs/servers_chs.list | awk '{print $3}')/$rt/$2"
        fi
    elif echo "$crashcore$custcorelink" | grep -qi 'concord'; then
        # 脚本包和版本号走 release（每周随内核一起发），其余静态资源走 jsDelivr
        rel="${concord_release_url:-https://github.com/foxlesbiao/shellcrash-concord/releases/latest/download}"
        case "$2" in
        ShellCrash.tar.gz | version) bin_url="$rel/$(echo "$2" | sed 's|.*/||')" ;;
        bin/* | public/* | rules/*)  bin_url="$update_url/ShellCrash/$2" ;;
        *)                           bin_url="$update_url/$2" ;;
        esac
    else
        bin_url="$update_url/$2"
    fi
    webget "$1" "$bin_url" "$3" "$4" "$5" "$6"
}