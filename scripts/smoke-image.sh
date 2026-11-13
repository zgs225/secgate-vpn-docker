#!/usr/bin/env bash
# 运行时冒烟：起一个容器 → 确认 X 栈 / noVNC / SOCKS5 / 图形客户端都活着 → 清理。
# 只验证「这个架构的镜像能跑起来」，不登录、不碰 tun 隧道，可以随便在 CI 或本机跑。
#
#   ./scripts/smoke-image.sh ghcr.io/zgs225/secgate-vpn-docker:latest
#   SMOKE_PORT=16080 ./scripts/smoke-image.sh local/img:test
set -uo pipefail

IMAGE="${1:?用法: ./scripts/smoke-image.sh <image> [超时秒数]}"
WAIT="${2:-90}"
NAME="secgate-smoke-$$"
PORT="${SMOKE_PORT:-16080}"

ok() { printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad() { printf '  \033[31m✘\033[0m %s\n' "$*"; FAIL=1; }
FAIL=0

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

image_field() { docker image inspect "$IMAGE" --format "{{$1}}" 2>/dev/null; }
ARCH=$(image_field .Architecture)
[ -n "$ARCH" ] || { echo "镜像不存在：$IMAGE" >&2; exit 1; }
echo "== 镜像 $IMAGE（$(image_field .Os)/$ARCH）"

args=(--detach --name "$NAME" --init -p "127.0.0.1:$PORT:6080")
# 宿主有 tun 就给容器（缺了也只影响登录后的隧道，不影响本冒烟）
if [ -e /dev/net/tun ]; then
    args+=(--device /dev/net/tun:/dev/net/tun --cap-add NET_ADMIN)
fi

echo "== 启动容器"
if ! docker run "${args[@]}" "$IMAGE" >/dev/null; then
    bad "容器启动失败"
    docker logs "$NAME" 2>&1 | tail -20
    exit 1
fi

echo "== 静态检查"
docker exec "$NAME" test -x /opt/sslvpnclient/files/bin/sslvpn \
    && ok "客户端二进制存在" || bad "客户端二进制缺失"
docker exec "$NAME" test -x /usr/local/bin/secgate-entrypoint.sh \
    && ok "entrypoint 存在" || bad "entrypoint 缺失"
docker exec "$NAME" sh -c 'fc-list | grep -qi sourcehan' \
    && ok "思源黑体已注册" || bad "字体没注册（界面会变成口口）"
ver=$(docker exec "$NAME" cat /opt/sslvpnclient/.client-version 2>/dev/null)
[ -n "$ver" ] && ok "客户端版本 $ver" || bad "缺少 /opt/sslvpnclient/.client-version"

echo "== 二进制架构与镜像架构一致"
got=$(docker exec "$NAME" od -An -tx1 -j18 -N2 /opt/sslvpnclient/files/bin/sslvpn 2>/dev/null | tr -d ' \n')
case "$(docker exec "$NAME" uname -m 2>/dev/null)" in
    x86_64) want=3e00 ;;
    aarch64) want=b700 ;;
    *) want="" ;;
esac
if [ -n "$want" ] && [ "$got" = "$want" ]; then
    ok "ELF 机器码 $got 与 $(docker exec "$NAME" uname -m) 匹配"
else
    bad "ELF 机器码 ${got:-?} 与容器架构不匹配（$(docker exec "$NAME" uname -m 2>/dev/null)）"
fi

echo "== 等待 noVNC 起来（最多 ${WAIT}s）"
code=000
for _ in $(seq 1 "$WAIT"); do
    code=$(curl -s -m 3 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/vnc.html" 2>/dev/null || echo 000)
    [ "$code" = "200" ] && break
    sleep 1
done
[ "$code" = "200" ] && ok "noVNC 返回 200" || bad "noVNC 返回 $code"

echo "== 进程检查"
for p in Xvfb openbox x11vnc; do
    docker exec "$NAME" pgrep -x "$p" >/dev/null && ok "$p 在跑" || bad "$p 未运行"
done
docker exec "$NAME" pgrep -f websockify >/dev/null && ok "websockify 在跑" || bad "websockify 未运行"
docker exec "$NAME" pgrep -x microsocks >/dev/null && ok "microsocks 在跑" || bad "microsocks 未运行"

echo "== 图形客户端存活（10s 后仍在）"
sleep 10
docker exec "$NAME" pgrep -f 'files/bin/sslvpn' >/dev/null \
    && ok "sslvpn 进程存活" || bad "sslvpn 没起来（架构不匹配/缺库？）"
if docker logs "$NAME" 2>&1 | grep -qiE 'exec format error|rc=126|Cannot execute'; then
    bad "日志里有 exec 失败，说明二进制架构不对"
    docker logs "$NAME" 2>&1 | tail -10
else
    ok "日志无 exec 失败"
fi

echo "== 容器日志（尾部）"
docker logs "$NAME" 2>&1 | tail -6 | sed 's/^/  /'

echo
if [ "$FAIL" = "0" ]; then
    printf '\033[32m== 冒烟通过：%s（%s）\033[0m\n' "$IMAGE" "$ARCH"
    exit 0
else
    printf '\033[31m== 冒烟失败：%s（%s）\033[0m\n' "$IMAGE" "$ARCH"
    exit 1
fi
