#!/usr/bin/env bash
# 从官方下载站取图形端安装包到 vendor/（不入库，开源仓库不转发厂商二进制）。
#
# 下载后先比官方 md5，再写一份本地 sha256 供 scripts/verify.sh 复核；
# 校验失败会删除文件并报错（几十 MB 的包偶发截断）。
set -euo pipefail
cd "$(dirname "$0")/.."

URL=https://sdwanapp.qianxin.com/download/sdwan-v6.0/hygon_kylin/KYLIN-X86_SDWANClient_Setup.deb
OUT=vendor/KYLIN-X86_SDWANClient_Setup.deb
MD5=49e3472a779e62be596117e4cefaee4a

mkdir -p vendor
echo "==> 下载 $URL"
curl -fL --retry 3 -m 900 -o "$OUT.part" "$URL"
mv "$OUT.part" "$OUT"

got=$(md5sum "$OUT" | awk '{print $1}')
if [ "$MD5" != "$got" ]; then
    echo "错误：md5 不匹配（期望 $MD5，实际 $got），删除下载文件" >&2
    rm -f "$OUT"
    exit 1
fi

( cd vendor && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
echo "==> 完成：$OUT (md5 $got, sha256 已写入 $OUT.sha256)"
