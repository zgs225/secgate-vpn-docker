#!/usr/bin/env bash
# 图形端自检：只读检查，不点击登录。
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

SERVICE=secgate-gui
# 厂商按架构发包，两个都校验；只取了一个也没关系，缺的那个跳过
DEB_AMD64=vendor/KYLIN-X86_SDWANClient_Setup.deb
DEB_ARM64=vendor/KYLIN-ARM_SDWANClient_Setup.deb
OFFICIAL_MD5_AMD64=49e3472a779e62be596117e4cefaee4a
OFFICIAL_MD5_ARM64=5d3ea8c60927bc902a166f14b6cbacd6
case "$(uname -m)" in
    aarch64 | arm64) HOST_DEB=$DEB_ARM64 ;;
    *) HOST_DEB=$DEB_AMD64 ;;
esac

# SOCKS5 探测目标：默认用 IP 字面量。宿主若跑 clash/mihomo 的 fake-ip DNS，
# 容器会把域名解析成 198.18.x.x，这类地址只在拦截流量的代理里生效，
# 交给 microsocks 必然连不上 → 误报。需要时用 SOCKS_TEST_URL 覆盖。
SOCKS_TEST_URL="${SOCKS_TEST_URL:-http://223.5.5.5/}"

ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$*"; }
info() { printf '  \033[36m·\033[0m %s\n' "$*"; }

# 取 HTTP 状态码。curl 失败时自己会输出 000，再补 `|| echo 000` 会拼成 "000000"。
http_code() {
    local out
    out=$(curl -s -m "${CURL_TIMEOUT:-10}" -o /dev/null -w '%{http_code}' "$@" 2>/dev/null) || true
    printf '%s' "${out:-000}"
}

echo "== 1. vendor deb 校验（官方 CDN md5 / 本地 sha256）=="
check_deb() {
  local deb=$1 official=$2 md5
  [ -f "$deb" ] || return 0
  md5=$(md5sum "$deb" | awk '{print $1}')
  info "$(basename "$deb") md5=$md5"
  [ "$md5" = "$official" ] && ok "与官方 md5 一致" || bad "md5 与官方不一致（下载被截断？）"
  if [ -f "$deb.sha256" ]; then
    if ( cd "$(dirname "$deb")" && sha256sum -c "$(basename "$deb").sha256" --status ); then
      ok "sha256 与 $(basename "$deb").sha256 一致"
    else
      bad "sha256 不一致"
    fi
  else
    info "无 $(basename "$deb").sha256（make fetch 会生成），跳过 sha256 校验"
  fi
}
check_deb "$DEB_AMD64" "$OFFICIAL_MD5_AMD64"
check_deb "$DEB_ARM64" "$OFFICIAL_MD5_ARM64"
[ -f "$HOST_DEB" ] || bad "缺少本机架构的 $(basename "$HOST_DEB")（先 make fetch）"

echo "== 2. 容器状态 =="
state=$(docker inspect -f '{{.State.Status}}' "$SERVICE" 2>/dev/null || echo missing)
health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}' "$SERVICE" 2>/dev/null || echo -)
if [ "$state" = running ]; then ok "running, health=$health"; else bad "状态 $state（先 make up）"; exit 1; fi

echo "== 3. X / 客户端进程 / 窗口 =="
docker exec "$SERVICE" xdpyinfo >/dev/null 2>&1 && ok "X (:1) 可用" || bad "X 不可用"
docker exec "$SERVICE" pgrep -x Xvfb >/dev/null && ok "Xvfb 在跑" || bad "Xvfb 未运行"
docker exec "$SERVICE" pgrep -x openbox >/dev/null && ok "openbox 窗口管理器在跑" || bad "openbox 未运行"
if docker exec "$SERVICE" pgrep -f 'files/bin/sslvpn' >/dev/null; then
  ok "SecGate 图形客户端在跑"
else
  bad "图形客户端未运行"
fi
win=$(docker exec "$SERVICE" xwininfo -root -tree 2>/dev/null | grep -c '"sslvpn"')
[ "$win" -ge 1 ] && ok "客户端窗口已映射（$win 个）" || bad "没找到客户端窗口"

echo "== 4. noVNC / VNC =="
info "noVNC: http://127.0.0.1:6080/vnc.html"
code=$(http_code http://127.0.0.1:6080/vnc.html)
[ "$code" = 200 ] && ok "vnc.html 200" || bad "vnc.html 返回 $code"
docker exec "$SERVICE" pgrep -x x11vnc >/dev/null && ok "x11vnc 在跑" || bad "x11vnc 未运行"

echo "== 5. SOCKS5 =="
info "映射: $(docker port "$SERVICE" 1080/tcp 2>/dev/null | head -1)"
docker exec "$SERVICE" pgrep -x microsocks >/dev/null && ok "microsocks 在跑" || bad "microsocks 未运行"
code=$(http_code --socks5-hostname 127.0.0.1:1080 "$SOCKS_TEST_URL")
case "$code" in
  000) bad "SOCKS5 转发失败（$SOCKS_TEST_URL 连不上）" ;;
  *)   ok "SOCKS5 转发正常（$SOCKS_TEST_URL → HTTP $code；非 2xx 也说明链路已通）" ;;
esac

echo "== 6. 隧道现状（未登录时应无 tun0）=="
docker exec "$SERVICE" sh -c 'ip -o link show tun0 2>/dev/null || echo "  (无 tun0 —— 还没在界面里登录，正常)"'
docker exec "$SERVICE" sh -c 'ip route | head -4'

echo "== 7. 界面截图 =="
mkdir -p screenshots
out="screenshots/gui-$(date +%H%M%S).png"
if docker exec "$SERVICE" scrot -o /tmp/_verify.png 2>/dev/null && docker cp "$SERVICE":/tmp/_verify.png "$out" >/dev/null 2>&1; then
  ok "已截图 → $out"
else
  bad "截图失败"
fi

cat <<'EOF'

下一步（人工）：浏览器打开 http://127.0.0.1:6080/vnc.html
  1. 右上角下拉默认是「国际版」，国内网关请切「国内版」
  2. 填服务器地址 / 端口号 → 连接
  3. 输账号密码 → 出现二次认证（短信/OTP）在这里输入
  4. 连上后：make verify 应能看到 tun0 与 0.0.0.0/1、128.0.0.0/1 路由
  5. 走代理：curl --socks5-hostname 127.0.0.1:1080 http://<内网地址>/
EOF
