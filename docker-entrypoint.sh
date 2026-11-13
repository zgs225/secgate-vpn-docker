#!/usr/bin/env bash
# 启动 Xvfb + openbox + x11vnc + noVNC + microsocks，然后拉起 SecGate Access 图形客户端。
set -uo pipefail

export DISPLAY="${DISPLAY:-:1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-root}"
export HOME="${HOME:-/root}"
SCREEN="${SCREEN:-1280x800x24}"

mkdir -p "$XDG_RUNTIME_DIR" /opt/sslvpnclient/log
chmod 700 "$XDG_RUNTIME_DIR"

log() { echo "[entrypoint] $*"; }

cleanup() {
    log "收到退出信号，清理子进程"
    jobs -p | xargs -r kill 2>/dev/null
    wait 2>/dev/null
}
trap cleanup EXIT INT TERM

# 1) X 服务器（软件 GL，Qt Quick 不依赖真实 GPU）
log "启动 Xvfb $DISPLAY ($SCREEN)"
Xvfb "$DISPLAY" -screen 0 "$SCREEN" -nolisten tcp +extension GLX +render -noreset \
    >/tmp/xvfb.log 2>&1 &
for _ in $(seq 1 50); do
    xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 && break
    sleep 0.2
done
xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 && log "X 就绪" || log "警告：X 未就绪"

# 2) 窗口管理器（Qt 的对话框/弹窗需要，否则二次认证窗口可能不显示）
openbox >/tmp/openbox.log 2>&1 &

# 3) VNC + WebSocket 桥接（noVNC 默认页面 /vnc.html）
x11vnc -display "$DISPLAY" -forever -shared -nopw -rfbport 5900 \
       -noxdamage -repeat -quiet -o /tmp/x11vnc.log &
log "启动 noVNC http://0.0.0.0:6080/vnc.html"
websockify --web=/usr/share/novnc 6080 127.0.0.1:5900 >/tmp/websockify.log 2>&1 &

# 4) SOCKS5 出口（登录成功后容器内流量经 tun0 进内网）
microsocks -i 0.0.0.0 -p 1080 &

# 5) 图形客户端（容器内已是 root，官方 gui_start.sh 的 pkexec 不需要）
log "启动 sslvpn 图形客户端"
while true; do
    /opt/sslvpnclient/files/bin/sslvpn >>/opt/sslvpnclient/log/gui.out 2>&1
    rc=$?
    log "sslvpn 退出 (rc=$rc)，3 秒后重启"
    sleep 3
done
