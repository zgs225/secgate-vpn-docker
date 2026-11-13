#!/usr/bin/env bash
# 从运行中的 secgate 容器导出 tun0 路由，生成 clash/mihomo ipcidr ruleset。
#
# 用法：
#   ./scripts/export-clash-ruleset.sh [容器名]                      # 输出到 stdout
#   EXCLUDE_CIDRS='192.168.0.0/16,10.0.0.0/8' ./scripts/export-clash-ruleset.sh
#
# 前提：容器已登录（`ip -o link show tun0` 有输出），否则会直接报错退出。
#
# EXCLUDE_CIDRS：需要排除的网段（逗号或空格分隔）。**请务必把你自己的 LAN 段排除**，
# 否则网关下发的 /16 之类汇总路由会把本地网络也带进 VPN。脚本另外会自动排除
# tun0 自身所在的那个 /24（那是隧道网关段，不需要再路由一次）。
set -euo pipefail

SERVICE="${1:-secgate-gui}"
TUN_DEV="${TUN_DEV:-tun0}"
EXCLUDE_CIDRS="${EXCLUDE_CIDRS:-}"

routes=$(docker exec "$SERVICE" ip -o route 2>/dev/null | awk -v d="dev $TUN_DEV" 'index($0, d) {print $1}' | sort -u)
if [ -z "$routes" ]; then
    echo "错误：$SERVICE 里没有 dev $TUN_DEV 的路由（未登录？）" >&2
    exit 1
fi

# 自动排除隧道自身网段：取 tun0 的本端地址，按 /24 归并
tun_cidr=""
tun_addr=$(docker exec "$SERVICE" ip -o -4 addr show "$TUN_DEV" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1) || true
if [ -n "${tun_addr:-}" ]; then
    tun_cidr="${tun_addr%.*}.0/24"
fi

excluded() {
    local cidr="$1" e
    [ -n "$tun_cidr" ] && [ "$cidr" = "$tun_cidr" ] && return 0
    for e in ${EXCLUDE_CIDRS//,/ }; do
        [ -n "$e" ] && [ "$cidr" = "$e" ] && return 0
    done
    return 1
}

emit() {
    echo "payload:"
    for cidr in $routes; do
        excluded "$cidr" && continue
        printf '  - "%s"\n' "$cidr"
    done
}

emit | grep -q '^  - ' || { echo "错误：排除后没有剩余网段（EXCLUDE_CIDRS 太宽？）" >&2; exit 1; }
emit
