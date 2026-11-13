# 奇安信 SecGate Access —— SD-WAN / SSL VPN 图形客户端容器（带浏览器可访问桌面）
#
# 为什么用图形端：该网关开启了「二次认证」，CLI 版（sslvpnclient/secgateaccess）没有对应
# 输入字段，认证会被服务端拒绝且只写一行 Login error 到日志、进程还不退出。图形端才有
# 二次认证弹窗，可以人工点/输验证码。
#
# 包来源（厂商官方下载站）：
#   https://sdwanapp.qianxin.com/download/sdwan-v6.0/hygon_kylin/KYLIN-X86_SDWANClient_Setup.deb
#   md5 49e3472a779e62be596117e4cefaee4a / Package sslvpnclient 1.1.3.1010701 / amd64
#   即「海光麒麟客户端」，linuxdeployqt 打包，自带 Qt5（含 Quick/QML）与字体，落盘 /opt/sslvpnclient
#
# 图形栈：Xvfb(软件 GL) + openbox + x11vnc + noVNC(websockify) → 浏览器打开 6080
# 出口：microsocks 提供 SOCKS5(1080)，流量走客户端建立的 tun0 全隧道
FROM ubuntu:24.04

LABEL org.opencontainers.image.title="secgate-access-gui" \
      org.opencontainers.image.description="QiAnXin SecGate Access SD-WAN/SSL VPN GUI client (Kylin/amd64) + noVNC + microsocks" \
      org.opencontainers.image.version="1.1.3.1010701" \
      org.opencontainers.image.source="https://github.com/zgs225/secgate-vpn-docker" \
      org.opencontainers.image.url="https://github.com/zgs225/secgate-vpn-docker" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive

# xvfb/x11vnc/openbox/novnc/websockify: 桌面与浏览器访问
# libgl1 + libgl1-mesa-dri: Qt Quick 需要 GL，Xvfb 下走 llvmpipe 软件渲染
# libxcb-* / libxkbcommon-x11-0: Qt xcb 平台插件运行期依赖
# scrot: 只用于 make shot 自检截图（很小）
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        xvfb x11vnc openbox novnc websockify x11-utils scrot \
        libgl1 libgl1-mesa-dri \
        libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 \
        libxcb-render-util0 libxcb-shape0 libxcb-xinerama0 libxcb-xkb1 \
        libxkbcommon-x11-0 libxkbcommon0 libfontconfig1 libfreetype6 \
        libdbus-1-3 libsm6 libice6 libxrender1 libxi6 libxtst6 libxext6 \
        libx11-6 libx11-xcb1 libxau6 libxdmcp6 \
        fonts-dejavu-core fontconfig \
        iproute2 microsocks procps \
 && rm -rf /var/lib/apt/lists/*

# 安装官方 deb（维护者脚本无 systemd 依赖，容器内可直接 dpkg -i）
COPY vendor/KYLIN-X86_SDWANClient_Setup.deb /tmp/
RUN dpkg -i /tmp/KYLIN-X86_SDWANClient_Setup.deb \
 && rm -f /tmp/*.deb \
 && test -x /opt/sslvpnclient/files/bin/sslvpn

COPY docker-entrypoint.sh /usr/local/bin/secgate-entrypoint.sh
RUN chmod +x /usr/local/bin/secgate-entrypoint.sh

# 客户端自带的思源黑体没有注册进 fontconfig，否则界面中文全是「口口」
RUN mkdir -p /usr/local/share/fonts/sslvpn \
 && cp /opt/sslvpnclient/files/bin/lib/fonts/*.ttf /usr/local/share/fonts/sslvpn/ \
 && fc-cache -f >/dev/null \
 && fc-list | grep -qi sourcehan

ENV DISPLAY=:1 \
    XDG_RUNTIME_DIR=/tmp/runtime-root \
    HOME=/root \
    QT_QUICK_BACKEND=software \
    LIBGL_ALWAYS_SOFTWARE=1 \
    QT_XCB_GL_INTEGRATION=none

WORKDIR /opt/sslvpnclient

# 6080 noVNC(http) / 5900 VNC(可选) / 1080 SOCKS5
EXPOSE 6080 5900 1080

ENTRYPOINT ["/usr/local/bin/secgate-entrypoint.sh"]
