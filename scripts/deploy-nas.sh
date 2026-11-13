#!/usr/bin/env bash
# 把图形端镜像部署到 NAS（Synology DSM 等，只要宿主有 docker + /dev/net/tun）
# 并（重）建容器。
#
#   NAS_HOST=nas ./scripts/deploy-nas.sh              # 幂等：镜像已在 NAS 上就跳过传输
#   NAS_HOST=nas FORCE_PUSH=1 ./scripts/deploy-nas.sh # 强制重推镜像
#
# 可覆盖的环境变量：
#   NAS_HOST        NAS 的 ssh 别名/主机名（默认 nas）
#   NAS_IP          NAS 的 IP（默认通过 ssh 在目标机上取 hostname -i）
#   IMAGE           镜像名（默认 local/secgate-gui:1.1.3.1010701）
#   NAS_BASE        NAS 上的数据目录（默认 /volume2/docker/secgate-vpn）
#   SOCKS_PORT      SOCKS5 对外端口（默认 1080，按需改，避免和其它 VPN 容器撞车）
#   VNC_PORT        noVNC 对外端口（默认 6080）
set -euo pipefail

NAME="${NAME:-secgate-gui}"
IMAGE="${IMAGE:-local/secgate-gui:1.1.3.1010701}"
NAS_HOST="${NAS_HOST:-nas}"
NAS_BASE="${NAS_BASE:-/volume2/docker/secgate-vpn}"
SOCKS_PORT="${SOCKS_PORT:-1080}"
VNC_PORT="${VNC_PORT:-6080}"
DOCKER=/var/packages/ContainerManager/target/usr/bin/docker

say() { printf '\033[36m==>\033[0m %s\n' "$*"; }
sshq() { ssh -o ConnectTimeout=10 "$NAS_HOST" "$@" 2>&1 \
    | grep -v 'WARNING: connection is not\|post-quantum\|store now\|may need to be upgraded' || true; }

command -v docker >/dev/null || { echo "本机没有 docker" >&2; exit 1; }
docker image inspect "$IMAGE" >/dev/null 2>&1 || { echo "本机缺少镜像 $IMAGE，先 make build" >&2; exit 1; }

NAS_IP="${NAS_IP:-$(sshq 'hostname -i 2>/dev/null | tr " " "\n" | grep -vE "^127\.|:" | head -1')}"
[ -n "$NAS_IP" ] || { echo "无法确定 NAS_IP，请显式传入（NAS_IP=x.x.x.x）" >&2; exit 1; }
say "目标 NAS：$NAS_HOST（$NAS_IP）"

if [ "${FORCE_PUSH:-0}" != "1" ] && sshq "sudo $DOCKER image inspect $IMAGE >/dev/null 2>&1 && echo present" | grep -q present; then
    say "NAS 上已有 $IMAGE，跳过传输"
else
    say "传输镜像（docker save | gzip | ssh docker load，视网络几分钟）"
    docker save "$IMAGE" | gzip -1 | ssh -o ConnectTimeout=10 "$NAS_HOST" "gunzip | sudo $DOCKER load"
fi

say "准备数据目录 $NAS_BASE"
sshq "sudo mkdir -p $NAS_BASE/runtime $NAS_BASE/log $NAS_BASE/root-home && sudo chmod -R 777 $NAS_BASE"

say "（重）建容器 $NAME   socks=$SOCKS_PORT  novnc=$VNC_PORT"
sshq "sudo $DOCKER rm -f $NAME >/dev/null 2>&1 || true; sudo $DOCKER run -d \
  --name $NAME --hostname $NAME --restart unless-stopped \
  --cap-add NET_ADMIN --device /dev/net/tun:/dev/net/tun \
  -e TZ=${TZ:-Asia/Shanghai} -e SCREEN=1280x800x24 \
  -p $SOCKS_PORT:1080 -p $VNC_PORT:6080 \
  --shm-size 512m \
  -v $NAS_BASE/runtime:/opt/sslvpnclient/runtime \
  -v $NAS_BASE/log:/opt/sslvpnclient/log \
  -v $NAS_BASE/root-home:/root \
  --log-opt max-size=10m --log-opt max-file=2 \
  $IMAGE >/dev/null && sudo $DOCKER ps --filter name=$NAME --format '{{.Names}} {{.Status}} {{.Ports}}'"

say "等待就绪"
for _ in $(seq 1 30); do
    if curl -fsS -m 3 -o /dev/null "http://$NAS_IP:$VNC_PORT/vnc.html" 2>/dev/null; then
        say "noVNC 就绪： http://$NAS_IP:$VNC_PORT/vnc.html"
        break
    fi
    sleep 2
done

cat <<EOF

下一步（人工，需要过二次认证）：
  1. 浏览器打开 http://$NAS_IP:$VNC_PORT/vnc.html
  2. 选「国内版/国际版」，填服务器地址与端口，登录并输入验证码
  3. 回来后验证： curl --socks5-hostname $NAS_IP:$SOCKS_PORT http://<内网地址>/
EOF
