
clash_check() { #启动前检查
    # 本版只有 concord 一个内核，不再有"换内核"的逻辑（core_exchange 已移除）
    check_core
    #预下载GeoIP数据库
    grep -qEi 'GEOIP,CN' "$CRASHDIR"/yamls/config.yaml && ! grep -Eq '^[[:space:]]*geodata-mode:' "$CRASHDIR"/yamls/*.yaml && check_geo Country.mmdb cn_mini.mmdb
    #预下载GeoSite数据库
    grep -qEi 'GEOSITE,' "$CRASHDIR"/yamls/config.yaml && ! grep -Eq '^[[:space:]]*geosite:' "$CRASHDIR"/yamls/*.yaml && check_geo GeoSite.dat geosite.dat
    #预下载cn.mrs数据库
    [ "$dns_mod" = "mix" ] || [ "$dns_mod" = "route" ] && ! grep -Eq '^[[:space:]]*cn:' "$CRASHDIR"/yamls/*.yaml && check_geo ruleset/cn.mrs mrs_geosite_cn.mrs
    return 0
}
