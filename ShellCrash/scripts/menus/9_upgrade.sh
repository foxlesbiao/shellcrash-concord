#!/bin/sh
# Copyright (C) Juewuy

[ -n "$__IS_MODULE_9_UPGRADE_LOADED" ] && return
__IS_MODULE_9_UPGRADE_LOADED=1

. "$CRASHDIR"/libs/check_dir_avail.sh
. "$CRASHDIR"/libs/check_cpucore.sh
. "$CRASHDIR"/libs/web_get_bin.sh
load_lang 9_upgrade

error_down() {
    btm_box "\033[33m$UPG_ERR_TRY_OTHER_SOURCE\033[0m" \
        "$UPG_ERR_LOCAL_INSTALL"
    sleep 1
}

# 更新/卸载功能菜单
upgrade() {
    while true; do
        if [ -z "$version_new" ]; then
            checkupdate
        fi
        [ -z "$core_v" ] && core_v=$crashcore
        core_v_new=$(eval echo \$"$crashcore"_v)
        top_box "\033[30;47m$UPG_TITLE\033[0m" \
            "" \
            "$UPG_CUR_DIR_SPACE(\033[32m$CRASHDIR\033[0m)：\033[36m$(dir_avail "$CRASHDIR" -h)\033[0m"
        [ "$(dir_avail "$CRASHDIR")" -le 5120 ] && [ "$CRASHDIR" = "$BINDIR" ] && {
            content_line "\033[33m$UPG_LOW_SPACE_HINT\033[0m"
        }
        separator_line "="
        btm_box "1) $UPG_MENU_SCRIPT\033[36m$UPG_MENU_SCRIPT_NAME\t\033[33m$versionsh_l\033[0m > \033[32m$version_new \033[36m$release_type\033[0m" \
            "2) 更新内核\t\t\033[33m$core_v\033[0m > \033[32m$core_v_new\033[0m" \
            "3) $UPG_MENU_GEO\033[32m$UPG_MENU_GEO_NAME\033[0m" \
            "4) $UPG_MENU_DB\033[35m$UPG_MENU_DB_NAME\033[0m" \
            "5) $UPG_MENU_CRT\033[33m$UPG_MENU_CRT_NAME\033[0m" \
            "6) \033[32mPAC\033[0m$UPG_MENU_PAC" \
            "7) \033[31m$UPG_MENU_UNINSTALL\033[0m" \
            "8) \033[36m$UPG_MENU_THANKS\033[0m" \
            "" \
            "0) $COMMON_BACK"
        read -r -p "$COMMON_INPUT> " num
        case "$num" in
        "" | 0)
            break
            ;;
        1)
            setscripts
            ;;
        2)
            setcore
            ;;
        3)
            setgeo
            ;;
        4)
            setdb
            ;;
        5)
            setcrt
            ;;
        6)
            if echo "$crashcore" | grep -qi 'concord'; then
                msg_alert "concord 没有 PAC 服务（不支持 external-ui），此功能不可用"
            else
                msg_alert -t 2 "$UPG_PAC_LINK\033[30;47m http://$host:$db_port/ui/pac \033[0m" \
                    "$UPG_PAC_GUIDE\033[4;32mhttps://juewuy.github.io/ehRUeewcv\033[0m"
            fi
            ;;
        7)
            . "$CRASHDIR"/menus/uninstall.sh && uninstall
            ;;
        8)
            comp_box "$UPG_THANKS_TITLE"
            btm_box "\033[32m$UPG_THANKS_ITEM_CLASH\033[0m" \
                "" \
                "" \
                "\033[32m$UPG_THANKS_ITEM_METACUBE\033[0m" \
                "$UPG_THANKS_ITEM_METACUBE_URL" \
                "" \
                "\033[32m$UPG_THANKS_ITEM_YACD\033[0m" \
                "$UPG_THANKS_ITEM_YACD_URL" \
                "" \
                "\033[32m$UPG_THANKS_ITEM_ZASH\033[0m" \
                "$UPG_THANKS_ITEM_ZASH_URL" \
                "" \
                "\033[32m$UPG_THANKS_ITEM_SUB\033[0m" \
                "$UPG_THANKS_ITEM_SUB_URL" \
                "" \
                "\033[32m$UPG_THANKS_ITEM_REF1ND\033[0m" \
                "$UPG_THANKS_ITEM_REF1ND_URL" \
                "" \
                "\033[32m$UPG_THANKS_ITEM_DUSTIN\033[0m" \
                "$UPG_THANKS_ITEM_DUSTIN_URL" \
                ""
            btm_box "$UPG_THANKS_SPECIAL"
            sleep 2
            ;;
        *)
            errornum
            ;;
        esac
    done
}

# 检查更新
checkupdate() {
    line_break
    separator_line "="
    content_line "\033[32m$UPG_CHECKING\033[0m"
    get_bin "$TMPDIR"/version_new version echooff
    [ "$?" = "0" ] && {
        version_new=$(cat "$TMPDIR"/version_new)
        get_bin "$TMPDIR"/version_new bin/version echooff
        content_line "\033[32m$UPG_CHECK_OK\033[0m"
        separator_line "="
    }
    if [ "$?" = "0" ]; then
        . "$TMPDIR"/version_new 2>/dev/null
    else
        content_line "\033[31m$UPG_CHECK_FAIL\033[0m"
        separator_line "="
        content_line "\033[33m更新源已固定为本仓库 release，请检查网络连通性\033[0m"
        sleep 2
    fi
    rm -rf "$TMPDIR"/version_new
}

# 更新脚本
getscripts() {
    line_break
    separator_line "="
    get_bin "$TMPDIR"/ShellCrash.tar.gz ShellCrash.tar.gz

    if [ "$?" != "0" ]; then
        content_line "\033[33m$UPG_DOWNLOAD_FAIL\033[0m"
        error_down
    else
        "$CRASHDIR"/start.sh stop 2>/dev/null
        # 解压
        content_line "$UPG_EXTRACTING"
        mkdir -p "$CRASHDIR" >/dev/null
        tar -zxf "$TMPDIR/ShellCrash.tar.gz" ${tar_para} -C "$CRASHDIR"/
        if [ $? -ne 0 ]; then
            content_line "\033[33m$UPG_EXTRACT_FAIL\033[0m"
            error_down
        else
            . "$CRASHDIR"/init.sh >/dev/null
            echo "$release_type" | grep -qE '^[0-9]' && setconfig userguide #回退时重新新手引导
            content_line "\033[32m$UPG_SCRIPT_OK\033[0m"
            separator_line "="
        fi
    fi
    rm -rf "$TMPDIR"/ShellCrash.tar.gz
    exit
}

setscripts() {
    while true; do
        comp_box "\033[33m$UPG_SCRIPT_WARN\033[0m" \
            "" \
            "$UPG_SCRIPT_CUR_VER\033[36m$versionsh_l\033[0m" \
            "$UPG_SCRIPT_NEW_VER\033[32m$version_new\033[0m"
        btm_box "1) $UPG_UPDATE_NOW" \
            "0) $COMMON_BACK"
        read -r -p "$COMMON_INPUT> " res
        case "$res" in
        "" | 0)
            break
            ;;
        1)
            # 下载更新
            getscripts
            # 提示
            msg_alert "\033[32m$UPG_SCRIPT_MGR_OK\033[0m"
            line_break
            exit 0
            ;;
        *)
            errornum
            ;;
        esac
    done
}

# 更新内核
# 手动设置内核架构
setcpucore() {
    cpucore_list="armv5 armv7 arm64 386 amd64 mipsle-softfloat mipsle-hardfloat mips-softfloat"

    comp_box "\033[31m$UPG_CPUCORE_HINT1\033[0m" \
        "$UPG_CPUCORE_HINT2" \
        "$UPG_CPUCORE_HINT3\033[36;4mhttps://juewuy.github.io/bdaz\033[0m"
    content_line "$UPG_CPUCORE_LIST"
    separator_line "-"

    echo "$cpucore_list" |
        awk '{for(i=1;i<=NF;i++) print i") "$i}' |
        while IFS= read -r line; do
            content_line "$line"
        done

    separator_line "="
    read -r -p "$COMMON_INPUT> " num
    [ -n "$num" ] && setcpucore=$(echo "$cpucore_list" | awk '{print $"'"$num"'"}')
    if [ -z "$setcpucore" ]; then
        cpucore=""
        msg_alert "\033[31m$UPG_CPUCORE_ERR\033[0m"
    else
        cpucore=$setcpucore
        setconfig cpucore "$cpucore"
    fi
}

# 手动指定内核类型
setcoretype() {
    # 只支持 concord，无需选择（本仓库专用版）
    crashcore=concord
    core_new=clash
}

# 下载内核文件
getcore() {
    # 调用下载工具
    . "$CRASHDIR"/libs/core_tools.sh

    [ -z "$crashcore" ] && crashcore=meta
    [ -z "$cpucore" ] && check_cpucore
    [ "$crashcore" = unknow ] && setcoretype
    core_new=clash
    # 获取在线内核文件
    line_break
    separator_line "="
    content_line "${UPG_GETTING_CORE_TEXT_PREFIX}${crashcore}${UPG_GETTING_CORE_TEXT_SUFFIX}"
    core_webget
    case "$?" in
    0)
        content_line "\033[32m${UPG_CORE_DOWNLOAD_OK_TEXT_PREFIX}${crashcore}${UPG_CORE_DOWNLOAD_OK_TEXT_SUFFIX}\033[0m"
        separator_line "="
        sleep 1
        ;;
    1)
        content_line "\033[31m$UPG_CORE_DOWNLOAD_FAIL_TEXT\033[0m"
        separator_line "="
        [ -z "$custcorelink" ] && error_down
        ;;
    *)
        content_line "\033[31m$UPG_CORE_DOWNLOAD_VERIFY_FAIL_TEXT\033[0m"
        content_line "\033[31m$UPG_CORE_DOWNLOAD_VERIFY_HINT_TEXT\033[0m"
        separator_line "="
        sleep 1
        rm -rf "${TMPDIR}"/core_new
        rm -rf "${TMPDIR}"/core_new.tar.gz
        setcpucore
        ;;
    esac
}
setcore() {
    while true; do
        # 获取核心及版本信息
        [ -z "$crashcore" ] && crashcore="unknow"
        [ -z "$zip_type" ] && zip_type="tar.gz"
        core_old=clash

        [ -z "$cpucore" ] && check_cpucore

        comp_box "$UPG_CORE_MENU_CURRENT\033[42;30m$crashcore\033[47;30m $core_v\033[0m" \
            "$UPG_CORE_MENU_SYS\033[32m$cpucore\033[0m" \
            "\033[36m$UPG_CORE_MENU_LOCAL_HINT\033[0m" \
            "" \
            "\033[33m$UPG_CORE_MENU_SELECT\033[0m"

        btm_box "1) \033[36m更新 Concord 内核\033[0m（从 shellcrash-concord 自动下载）" \
            "2) CPU架构 $cpucore" \
            "3) 重新下载当前内核" \
            "" \
            "0) $COMMON_BACK"
        read -r -p "$COMMON_INPUT> " num
        case "$num" in
        "" | 0)
            break
            ;;
        1)
            # 按当前 CPU 架构选对应内核（nikki-concord 只出这 4 个架构）
            crashcore=concord
            case "$cpucore" in
            arm64)  concord_arch='aarch64_generic' ;;
            amd64)  concord_arch='x86_64' ;;
            *)      concord_arch='' ;;
            esac
            if [ -z "$concord_arch" ]; then
                msg_alert "\033[31m当前架构 $cpucore 暂无 concord 内核\033[0m" \
                    "\033[33m可用: arm64 / amd64\033[0m"
                continue
            fi
            custcorelink="https://ghfast.top/https://github.com/foxlesbiao/shellcrash-concord/releases/latest/download/concord-$concord_arch.gz"
            getcore
            break
            ;;
        2)
            setcpucore
            break
            ;;
        3)
            getcore
            break
            ;;
        *)
            errornum
            ;;
        esac
    done
}

# 数据库
# 下载Geo文件
getgeo() {
    # 生成链接
    line_break
    separator_line "="
    content_line "$UPG_GEO_GETTING"
    get_bin "$TMPDIR"/"${geoname}" bin/geodata/"$geotype"
    if [ "$?" = "1" ]; then
        content_line "\033[31m$UPG_DOWNLOAD_FAIL\033[0m"
        error_down
    else
        echo "$geoname" | grep -Eq '.mrs|.srs|.tar.gz' && {
            geofile='ruleset/'
            [ ! -d "$BINDIR"/ruleset ] && mkdir -p "$BINDIR"/ruleset
        }
        if echo "$geoname" | grep -Eq '.tar.gz'; then
            tar -zxf "$TMPDIR"/"${geoname}" ${tar_para} -C "$BINDIR"/"${geofile}" >/dev/null
            if [ $? -ne 0 ]; then
                content_line "$UPG_EXTRACT_FAIL"
                separator_line "="
                sleep 1
                line_break
                rm -rf "$TMPDIR"/${geoname}
                exit 1
            fi
            rm -rf "$TMPDIR"/${geoname}
        else
            mv -f "$TMPDIR"/"${geoname}" "$BINDIR"/"${geofile}""${geoname}"
        fi
        content_line "\033[32m${UPG_GEO_OK_PREFIX}${geotype}${UPG_GEO_OK_SUFFIX}\033[0m"
        geo_v="$(echo "$geotype" | awk -F "." '{print $1}')_v"
        setconfig "$geo_v" "$GeoIP_v"
    fi
    sleep 1
}

getcustgeo() {
    line_break
    separator_line "="
    content_line "$UPG_GEO_LINKING"
    webget "$TMPDIR"/"$geoname" "$custgeolink"
    if [ "$?" = "1" ]; then
        content_line "\033[31m$UPG_DOWNLOAD_FAIL\033[0m"
        error_down
    else
        echo "$geoname" | grep -Eq '.mrs|.srs' && {
            geofile='ruleset/'
            [ ! -d "$BINDIR"/ruleset ] && mkdir -p "$BINDIR"/ruleset
        }
        mv -f "$TMPDIR"/"${geoname}" "$BINDIR"/"${geofile}""${geoname}"
        content_line "\033[32m${UPG_GEO_OK_PREFIX}${geotype}${UPG_GEO_OK_SUFFIX}\033[0m"
        separator_line "="
    fi
    sleep 1
}

checkcustgeo() {
    while true; do
        [ "$api_tag" = "latest" ] && api_url=latest || api_url="tags/$api_tag"
        [ ! -s "$TMPDIR"/geo.list ] && {
            comp_box "\033[32m$UPG_GEO_FIND_TITLE\033[0m"
            webget "$TMPDIR"/github_api https://api.github.com/repos/${project}/releases/${api_url}
            release_tag=$(cat "$TMPDIR"/github_api | grep '"tag_name":' | awk -F '"' '{print $4}')
            # concord 只读 mmdb 和 mrs（不支持 GeoIP.dat / GeoSite.dat / srs）
            if echo "$crashcore" | grep -qi 'concord'; then
                geo_pat='country.*\.mmdb"$|.*\.mrs'
            else
                geo_pat='geosite.*\.dat"$|country.*\.mmdb"$|.*.mrs|.*.srs'
            fi
            cat "$TMPDIR"/github_api | grep "browser_download_url" | grep -oE 'releases/download.*' | grep -oiE "$geo_pat" | sed 's|.*/||' | sed 's/"//' >"$TMPDIR"/geo.list
            rm -rf "$TMPDIR"/github_api
        }
        if [ -s "$TMPDIR"/geo.list ]; then
            comp_box "$UPG_GEO_SELECT"
            awk '{print NR") "$1}' "$TMPDIR/geo.list" |
                while IFS= read -r line; do
                    content_line "$line"
                done
            content_line ""
            content_line "0) $COMMON_BACK"
            separator_line "="
            read -r -p "$COMMON_INPUT> " num
            case "$num" in
            "" | 0)
                break
                ;;
            *[!0-9]*)
                errornum
                ;;
            *)
                if [ "$num" -le "$(wc -l < "$TMPDIR/geo.list")" ]; then
                    geotype=$(sed -n "$num"p "$TMPDIR"/geo.list)
                    echo "$geotype" | grep -qiE 'GeoSite\.dat' && geoname=GeoSite.dat
                    echo "$geotype" | grep -qiE 'Country\.mmdb' && geoname=Country.mmdb
                    echo "$geotype" | grep -qiE '\.(srs|mrs)$' && geoname="$geotype"
                    custgeolink=https://github.com/${project}/releases/download/${release_tag}/${geotype}
                    getcustgeo
                else
                    errornum
                    break
                fi
                ;;
            esac
        else
            msg_alert "\033[31m$UPG_CORE_CHECK_FAIL_HINT\033[0m"
        fi
    done
}

# 下载自定义数据库文件
setcustgeo() {
    while true; do
        rm -rf "$TMPDIR"/geo.list
        comp_box "\033[36m$UPG_GEO_CUSTOM_HINT\033[0m" \
            "\033[32m$UPG_GEO_CUSTOM_HINT2\033[0m" \
            "\033[31m$UPG_GEO_CUSTOM_HINT3\033[0m" \
            "\033[33m$UPG_GEO_CUSTOM_HINT4\033[0m"

        content_line "\033[0m$UPG_GEO_SOURCE_TITLE\033[0m"
        separator_line "-"
        content_line "1) \033[36;4mhttps://github.com/MetaCubeX/meta-rules-dat\033[0m"
        sub_content_line "$UPG_GEO_LOCAL_ONLY1"

        if ! echo "$crashcore" | grep -qi 'concord'; then
            content_line "2) \033[36;4mhttps://github.com/DustinWin/ruleset_geodata\033[0m"
            sub_content_line "$UPG_GEO_LOCAL_ONLY1"

            content_line "3) \033[36;4mhttps://github.com/DustinWin/ruleset_geodata\033[0m"

            content_line "5) \033[36;4mhttps://github.com/Loyalsoldier/geoip\033[0m"
            sub_content_line "$UPG_GEO_LOCAL_ONLY4"
        fi

        content_line "4) \033[36;4mhttps://github.com/DustinWin/ruleset_geodata\033[0m"
        sub_content_line "$UPG_GEO_LOCAL_ONLY3"

        content_line "$UPG_GEO_CUSTOM_LINK"
        content_line ""
        content_line "0) $COMMON_BACK"
        separator_line "="
        read -r -p "$COMMON_INPUT> " num
        case "$num" in
        "" | 0)
            break
            ;;
        1)
            project=MetaCubeX/meta-rules-dat
            api_tag=latest
            checkcustgeo
            ;;
        2)
            project=DustinWin/ruleset_geodata
            api_tag=mihomo-geodata
            checkcustgeo
            ;;
        3)
            project=DustinWin/ruleset_geodata
            api_tag=sing-box-ruleset
            checkcustgeo
            ;;
        4)
            project=DustinWin/ruleset_geodata
            api_tag=mihomo-ruleset
            checkcustgeo
            ;;
        5)
            project=Loyalsoldier/geoip
            api_tag=latest
            checkcustgeo
            ;;
        9)
            line_break
            read -r -p "$UPG_GEO_LINK_HINT" link
            [ -n "$link" ] && custgeolink="$link"
            getgeo
            ;;
        *)
            errornum
            ;;
        esac
    done
}

setgeo() {
    while true; do
        . $CFG_PATH >/dev/null
        [ -n "$cn_mini_v" ] && geo_type_des=$UPG_GEO_TYPE_LITE || geo_type_des=$UPG_GEO_TYPE_FULL
        comp_box "\033[33m$UPG_GEO_CHOOSE_HINT\033[0m" \
            "$UPG_GEO_LATEST\033[32m$GeoIP_v\033[0m" \
            "" \
            "$UPG_GEO_CHOOSE"

        # concord 只吃 CIDR 文本 / mmdb / mrs；GeoSite.dat 和 srs 已移除
        btm_box "$UPG_GEO_ITEM1\t\033[33m$china_ip_list_v\033[0m" \
            "$UPG_GEO_ITEM2\t\033[33m$china_ipv6_list_v\033[0m" \
            "" \
            "$UPG_GEO_ITEM3\t\033[33m$cn_mini_v\033[0m" \
            "$UPG_GEO_ITEM5" \
            "" \
            "0) $COMMON_BACK"
        read -r -p "$COMMON_INPUT> " num
        case "$num" in
        "" | 0)
            break
            ;;
        1)
            geotype=china_ip_list.txt
            geoname=cn_ip.txt
            getgeo
            ;;
        2)
            geotype=china_ipv6_list.txt
            geoname=cn_ipv6.txt
            getgeo
            ;;
        3)
            geotype=cn_mini.mmdb
            geoname=Country.mmdb
            getgeo
            ;;
        4)
            geotype=mrs.tar.gz
            geoname=mrs.tar.gz
            getgeo
            ;;
        5)
            while true; do
                comp_box "\033[33m${UPG_GEO_CLEAN_HINT1_PREFIX}${CRASHDIR}${UPG_GEO_CLEAN_HINT1_SUFFIX}\033[0m" \
                    "$UPG_GEO_CLEAN_HINT2"
                btm_box "1) $UPG_GEO_CLEAN_CONFIRM" \
                    "0) $COMMON_BACK"
                read -r -p "$COMMON_INPUT> " res
                case "$res" in
                "" | 0)
                    break
                    ;;
                1)
                    for file in cn_ip.txt cn_ipv6.txt *.mmdb *.metadb *.dat; do
                        rm -rf "$CRASHDIR"/$file
                    done
                    for var in Country_v cn_mini_v china_ip_list_v china_ipv6_list_v mrs_geosite_cn_v mrs_v; do
                        setconfig $var
                    done
                    rm -rf "$CRASHDIR"/ruleset/*
                    msg_alert "\033[33m$UPG_GEO_CLEAN_OK\033[0m"
                    break
                    ;;
                *)
                    errornum
                    ;;
                esac
            done
            ;;
        *)
            errornum
            ;;
        esac
    done
}

# Dashboard
getdb() {
    # concord 不支持 external-ui（/ui 返回 501），面板由 uhttpd 在 8090 托管
    echo "$crashcore" | grep -qi 'concord' && hostdir=":8090"
    dblink="${update_url}/"
    line_break
    separator_line "="
    content_line "$UPG_DB_GETTING"
    get_bin "$TMPDIR"/clashdb.tar.gz bin/dashboard/${db_type}.tar.gz
    if [ "$?" = "1" ]; then
        content_line "\033[31m$UPG_DOWNLOAD_FAIL\033[0m"
        error_down
        return 1
    else
        content_line "\033[33m$UPG_DB_DOWNLOAD_OK\033[0m"
        mkdir -p "$dbdir" >/dev/null
        tar -zxf "$TMPDIR/clashdb.tar.gz" ${tar_para} -C "$dbdir" >/dev/null
        if [ $? -ne 0 ]; then
            content_line "$UPG_EXTRACT_FAIL"
            separator_line "="
            line_break
            sleep 1
            rm -rf "$TMPDIR"/clashfm.tar.gz
            exit 1
        fi

        #修改默认host和端口
        if [ "$db_type" = "clashdb" -o "$db_type" = "meta_db" -o "$db_type" = "zashboard" ]; then
            sed -i "s/127.0.0.1/${host}/g" "$dbdir"/assets/*.js
            sed -i "s/9090/${db_port}/g" "$dbdir"/assets/*.js
        elif [ "$db_type" = "meta_xd" ]; then
            sed -i "s/127.0.0.1:9090/${host}:${db_port}/g" "$dbdir"/_nuxt/*.js
        else
            sed -i "s/127.0.0.1:9090/${host}:${db_port}/g" "$dbdir"/*.html
        fi
        #写入配置文件
        setconfig hostdir "'$hostdir'"
        content_line "\033[32m$UPG_DB_OK\033[0m"
        content_line "\033[36m$UPG_DB_REFRESH_HINT\033[0m"
        separator_line "="
        sleep 1
        rm -rf "$TMPDIR"/clashdb.tar.gz
    fi
    sleep 1
}

dbdir() {
    if [ -f /www/clash/CNAME ] || [ -f "$CRASHDIR"/ui/CNAME ]; then
        comp_box "\033[33m$UPG_DB_INSTALLED\033[0m"
        btm_box "$UPG_DB_UPGRADE" \
            "0) $COMMON_BACK"
        read -r -p "$COMMON_INPUT> " res
        if [ "$res" = 1 ]; then
            rm -rf "$BINDIR"/ui
            [ -f /www/clash/CNAME ] && rm -rf /www/clash && dbdir=/www/clash
            [ -f "$CRASHDIR"/ui/CNAME ] && rm -rf "$CRASHDIR"/ui && dbdir="$CRASHDIR"/ui
            getdb
        else
            msg_alert "\033[33m$UPG_DB_CANCEL\033[0m"
            return 1
        fi
    elif [ -w /www ] && [ -n "$(pidof nginx)" ]; then
        comp_box "$UPG_DB_DIR_SELECT"
        btm_box "${UPG_DB_DIR_1_PREFIX}${CRASHDIR}${UPG_DB_DIR_1_SUFFIX}" \
            "$UPG_DB_DIR_2" \
            "" \
            "0) $COMMON_BACK"
        read -r -p "$COMMON_INPUT> " num
        case "$num" in
        "" | 0)
            return 0
            ;;
        1)
            dbdir="$CRASHDIR"/ui
            echo "$crashcore" | grep -qi 'concord' && hostdir=":8090" || hostdir=": $db_port/ui"
            getdb
            ;;
        2)
            dbdir=/www/clash
            hostdir='/clash'
            getdb
            ;;
        *)
            errornum
            return 1
            ;;
        esac
    else
        dbdir="$CRASHDIR"/ui
        hostdir=":$db_port/ui"
        getdb
    fi
}

setdb() {
    while true; do
        comp_box "\033[36m$UPG_DB_TITLE\033[0m" \
            "\033[32m$UPG_DB_TITLE2\033[0m" \
            "" \
            "$UPG_DB_SELECT"
        # 只保留 zashboard（concord 唯一可用的面板），其余是 mihomo/clash 专属
        btm_box "$UPG_DB_INSTALL_1" \
            "$UPG_DB_UNINSTALL" \
            "" \
            "0) $COMMON_BACK"
        read -r -p "$COMMON_INPUT> " num
        case "$num" in
        "" | 0)
            break
            ;;
        1)
            # concord 不支持 external-ui，面板由 uhttpd 在 :8090 托管
            db_type=zashboard
            dbdir
            ;;
        2)
            while true; do
                comp_box "$UPG_DB_UNINSTALL_CONFIRM"
                btm_box "$UPG_DB_UNINSTALL_YES" \
                    "0) $COMMON_BACK"
                read -r -p "$COMMON_INPUT> " res
                case "$res" in
                "" | 0)
                    break
                    ;;
                1)
                    rm -rf /www/clash
                    rm -rf "$CRASHDIR"/ui
                    rm -rf "$BINDIR"/ui
                    msg_alert "\033[31m$UPG_DB_UNINSTALL_OK\033[0m"
                    break
                    ;;
                *)
                    errornum
                    ;;
                esac
            done
            ;;
        *)
            errornum
            ;;
        esac
    done
}

# 根证书
getcrt() {
    line_break
    separator_line "="
    content_line "$UPG_DB_GETTING"
    get_bin "$TMPDIR"/ca-certificates.crt bin/fix/ca-certificates.crt echooff
    if [ "$?" = "1" ]; then
        content_line "\033[31m$UPG_DOWNLOAD_FAIL\033[0m"
        error_down
    else
        [ "$systype" = 'mi_snapshot' ] && cp -f "$TMPDIR"/ca-certificates.crt "$CRASHDIR"/tools #镜像化设备特殊处理
        [ -f "$openssldir"/certs ] && rm -rf "$openssldir"/certs                                #如果certs不是目录而是文件则删除并创建目录
        mkdir -p "$openssldir"/certs
        mv -f "$TMPDIR"/ca-certificates.crt "$crtdir"
        webget /dev/null https://baidu.com echooff rediron skipceroff
        if [ "$?" = "1" ]; then
            export CURL_CA_BUNDLE="$crtdir"
            echo "export CURL_CA_BUNDLE=$crtdir" >>/etc/profile
        fi
        content_line "\033[32m$UPG_CRT_DB_OK\033[0m"
        separator_line "="
        sleep 1
    fi
}

setcrt() {
    while true; do
        openssldir="$(openssl version -d 2>&1 | awk -F '"' '{print $2}')"
        if [ -d "$openssldir/certs/" ]; then
            crtdir="$openssldir/certs/ca-certificates.crt"
        else
            crtdir="/etc/ssl/certs/ca-certificates.crt"
        fi

        if [ -n "$openssldir" ]; then
            line_break
            separator_line "="
            content_line "$UPG_CRT_TITLE1"
            content_line "\033[33m$UPG_CRT_TITLE2\033[0m"
            content_line "\033[31m$UPG_CRT_TITLE3\033[0m"
            if [ -f "$crtdir" ]; then
                content_line ""
                content_line "\033[33m$UPG_CRT_EXISTS\033[0m"
                content_line "\033[33m（$crtdir）\033[0m"
            fi
            separator_line "="

            if [ -f "$crtdir" ]; then
                content_line "$UPG_CRT_UPDATE"
            else
                content_line "$UPG_CRT_INSTALL"
            fi
            content_line "0) $COMMON_BACK"
            separator_line "="
            read -r -p "$COMMON_INPUT> " res
            case "$res" in
            "" | 0)
                break
                ;;
            1)
                getcrt
                break
                ;;
            *)
                errornum
                continue
                ;;
            esac

        else
            msg_alert "\033[33m$UPG_CRT_WARN\033[0m"
            break
        fi

    done
}

# 写入配置文件
saveserver() {
    setconfig update_url "'$update_url'"
    setconfig url_id "$url_id"
    setconfig release_type "$release_type"
    version_new=''
    msg_alert -t 0 "\033[32m$UPG_SOURCE_SWITCH_OK\033[0m"
}

# 安装源
setserver() {
    while true; do
        line_break
        LISTFILE="$CRASHDIR"/configs/servers_"$i18n".list
        [ -z "$release_type" ] && release_name=$UPG_SOURCE_UNSET
        [ -n "$release_type" ] && release_name="$release_type$UPG_SOURCE_ROLLBACK_TAG"
        [ "$release_type" = stable ] && release_name=$UPG_SOURCE_STABLE_TEXT
        [ "$release_type" = master ] && release_name=$UPG_SOURCE_MASTER_TEXT
        [ "$release_type" = dev ] && release_name=$UPG_SOURCE_DEV_TEXT
        [ -n "$url_id" ] && url_name=$(grep "$url_id" "$LISTFILE" 2>/dev/null | awk '{print $2}') || url_name="$update_url"

        comp_box "\033[30;47m$UPG_SOURCE_TITLE\033[0m" \
            "" \
            "$UPG_SOURCE_CUR_VER\033[4;33m$release_name\033[0m" \
            "$UPG_SOURCE_CUR_URL\n\033[4;32m$url_name\033[0m"

        grep -E "^1|^2" "$LISTFILE" |
            awk '{print NR") "$2}' |
            while IFS= read -r line; do
                content_line "$line"
            done

        btm_box "" \
            "$UPG_SOURCE_SWITCH_STABLE" \
            "$UPG_SOURCE_SWITCH_MASTER" \
            "$UPG_SOURCE_SWITCH_DEV" \
            "" \
            "$UPG_SOURCE_CUSTOM" \
            "$UPG_SOURCE_ROLLBACK" \
            "" \
            "0) $COMMON_BACK"
        read -r -p "$COMMON_INPUT> " num
        case "$num" in
        "" | 0)
            checkupdate=false
            break
            ;;
        [1-99])
            url_id_new=$(grep -E "^1|$release_name" "$LISTFILE" | sed -n "$num"p | awk '{print $1}')
            if [ -z "$url_id_new" ]; then
                errornum
                continue
            elif [ "$url_id_new" -ge 200 ]; then
                update_url=$(grep -E "^1|$release_name" "$LISTFILE" | sed -n "$num"p | awk '{print $3}')
                url_id=''
                saveserver
                break
            else
                url_id=$url_id_new
                update_url=''
                saveserver
                break
            fi
            unset url_id_new
            ;;
        a)
            release_type=stable
            [ -z "$url_id" ] && url_id=101
            saveserver
            ;;
        b)
            release_type=master
            [ -z "$url_id" ] && url_id=101
            saveserver
            ;;
        c)
            while true; do
                comp_box "\033[33m$UPG_SOURCE_DEV_WARN1\033[0m" \
                    "\033[33m$UPG_SOURCE_DEV_WARN2\033[0m" \
                    "$UPG_SOURCE_DEV_WARN3"
                content_line "$UPG_SOURCE_DEV_CONFIRM"
                separator_line "-"
                btm_box "$UPG_SOURCE_DEV_YES" \
                    "0) $COMMON_BACK"
                read -r -p "$COMMON_INPUT> " res
                case "$res" in
                "" | 0)
                    break
                    ;;
                1)
                    release_type=dev
                    [ -z "$url_id" ] && url_id=101
                    saveserver
                    break
                    ;;
                *)
                    errornum
                    ;;
                esac
            done
            ;;
        d)
            comp_box "\033[36m$UPG_SOURCE_CUSTOM_HINT\033[0m" \
                "$UPG_CUSTOM_CORE_LINK_HINT3"
            read -r -p "$UPG_SOURCE_CUSTOM_INPUT" update_url
            if [ "$update_url" = 0 ]; then
                continue
            elif [ ! -z "$update_url" ]; then
                url_id=''
                release_type=''
                saveserver
            fi
            ;;
        e)
            if [ -n "$url_id" ] && [ "$url_id" -lt 200 ]; then
                line_break
                separator_line "="
                content_line "\033[32m$UPG_SOURCE_VER_GETTING\033[0m"
                . "$CRASHDIR"/libs/web_get_lite.sh
                list=$(web_get_lite https://api.github.com/repos/juewuy/ShellCrash/tags | grep -E '"name": "[0-9]' | cut -d '"' -f4)
                if [ "$?" = "0" ]; then
                    content_line "\033[32m$UPG_SOURCE_VER_OK\033[0m"
                    separator_line "="

                    line_break
                    separator_line "="
                    content_line "\033[31m$UPG_SOURCE_ROLLBACK_SELECT\033[0m"
                    list_box "$list"
                    btm_box "" \
                        "0) $COMMON_BACK"
                    read -r -p "$COMMON_INPUT> " num
                    if [ -z "$num" ] || [ "$num" = 0 ]; then
                        continue
                    elif [ "$num" -le $(echo "$list" | awk 'END{print NR}') ]; then
                        release_type=$(echo "$list" | sed -n "$num"p)
                        update_url=''
                        saveserver
                    else
                        errornum
                        continue
                    fi
                else
                    content_line "\033[31m$UPG_SOURCE_ROLLBACK_FAIL\033[0m"
                    separator_line "="
                    sleep 1
                    continue
                fi
                rm -rf "$TMPDIR"/tags
            else
                msg_alert "\033[31m$UPG_SOURCE_ROLLBACK_NOTSUP\033[0m" \
                    "\033[31m$UPG_SOURCE_ROLLBACK_HINT\033[0m"
                continue
            fi
            ;;
        *)
            errornum
            ;;
        esac
    done
}
