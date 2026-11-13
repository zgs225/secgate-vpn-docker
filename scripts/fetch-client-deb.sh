#!/usr/bin/env bash
# 从官方下载站取图形端安装包到 vendor/（不入库，开源仓库不转发厂商二进制）。
#
# 厂商按 CPU 架构分别发包：
#   amd64  「海光麒麟」 hygon_kylin/KYLIN-X86_SDWANClient_Setup.deb
#   arm64  「鲲鹏麒麟」 kunpeng_kylin/KYLIN-ARM_SDWANClient_Setup.deb（与飞腾麒麟同一 md5）
#
#   ./scripts/fetch-client-deb.sh          # 只取本机架构的包（默认）
#   ./scripts/fetch-client-deb.sh all      # amd64 + arm64 都取（多架构构建/CI 用）
#   ./scripts/fetch-client-deb.sh arm64    # 指定架构
#
# 已存在且 md5 正确的包会跳过下载；每个包下载后先比官方 md5，再写一份本地 sha256 供
# scripts/verify.sh 复核；校验失败会删除文件并报错（几十 MB 的包偶发截断）。
set -euo pipefail
cd "$(dirname "$0")/.."

BASE=https://sdwanapp.qianxin.com/download/sdwan-v6.0
# 架构|文件名|下载路径|官方 md5（来自下载站 /data/ 接口的 file_md5）
DEBS=(
    "amd64|KYLIN-X86_SDWANClient_Setup.deb|hygon_kylin/KYLIN-X86_SDWANClient_Setup.deb|49e3472a779e62be596117e4cefaee4a"
    "arm64|KYLIN-ARM_SDWANClient_Setup.deb|kunpeng_kylin/KYLIN-ARM_SDWANClient_Setup.deb|5d3ea8c60927bc902a166f14b6cbacd6"
)

host_arch() {
    case "$(uname -m)" in
        x86_64 | amd64) echo amd64 ;;
        aarch64 | arm64) echo arm64 ;;
        *) uname -m ;;
    esac
}

want="${1:-$(host_arch)}"
[ "$want" = "all" ] || [ "$want" = "host" ] || true

mkdir -p vendor
found=0
for entry in "${DEBS[@]}"; do
    IFS='|' read -r arch file path md5 <<<"$entry"
    if [ "$want" != "all" ] && [ "$want" != "$arch" ]; then
        continue
    fi
    found=1
    out="vendor/$file"
    url="$BASE/$path"

    if [ -f "$out" ] && [ "$(md5sum "$out" | awk '{print $1}')" = "$md5" ]; then
        echo "==> 已有 $out（md5 $md5），跳过下载"
    else
        echo "==> 下载 $arch: $url"
        curl -fL --retry 3 -m 900 -o "$out.part" "$url"
        got=$(md5sum "$out.part" | awk '{print $1}')
        if [ "$md5" != "$got" ]; then
            echo "错误：$arch 包 md5 不匹配（期望 $md5，实际 $got），删除下载文件" >&2
            rm -f "$out.part"
            exit 1
        fi
        mv "$out.part" "$out"
    fi
    ( cd vendor && sha256sum "$file" > "$file.sha256" )
    echo "==> 完成：$out (md5 $(md5sum "$out" | awk '{print $1}'), sha256 已写入 $out.sha256)"
done

if [ "$found" = "0" ]; then
    echo "未知架构：$want（可选：amd64 / arm64 / all）" >&2
    exit 1
fi
