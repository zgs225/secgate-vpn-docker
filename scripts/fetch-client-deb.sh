#!/usr/bin/env bash
# 从官方下载站取客户端安装包到 vendor/（不入库，开源仓库不转发厂商二进制）。
#
#   ./scripts/fetch-client-deb.sh gui   # 海光麒麟/amd64 图形端（默认）
#   ./scripts/fetch-client-deb.sh cli   # Ubuntu 命令行端
#
# 下载后会用官方 md5 校验；校验失败会删除文件并报错（大文件偶发截断）。
set -euo pipefail
cd "$(dirname "$0")/.."

BASE=https://sdwanapp.qianxin.com/download

gui() {
    local url="$BASE/sdwan-v6.0/hygon_kylin/KYLIN-X86_SDWANClient_Setup.deb"
    local out=vendor/KYLIN-X86_SDWANClient_Setup.deb
    local md5=49e3472a779e62be596117e4cefaee4a
    fetch "$url" "$out" "$md5"
}

cli() {
    local url="$BASE/sdwan-v6.0/ubuntu/Ubuntu_SDWANClient_Setup.deb"
    local out=vendor/Ubuntu_SDWANClient_Setup.deb
    local md5=17bad1a9f4da50121cceaf09bb97f7d6
    fetch "$url" "$out" "$md5"
}

fetch() {
    local url="$1" out="$2" md5="$3"
    mkdir -p vendor
    echo "==> 下载 $url"
    curl -fL --retry 3 -m 900 -o "$out.part" "$url"
    mv "$out.part" "$out"
    local got; got=$(md5sum "$out" | awk '{print $1}')
    if [ -n "$md5" ] && [ "$md5" != "$got" ]; then
        echo "错误：md5 不匹配（期望 $md5，实际 $got），删除下载文件" >&2
        rm -f "$out"
        exit 1
    fi
    echo "==> 完成：$out (md5 $got)"
}

case "${1:-gui}" in
    gui) gui ;;
    cli) cli ;;
    *) echo "用法: $0 [gui|cli]" >&2; exit 1 ;;
esac
