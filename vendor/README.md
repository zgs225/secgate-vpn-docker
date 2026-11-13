# vendor/

厂商客户端安装包**不入库**（开源仓库不转发第三方二进制，也避免几十 MB 的 blob 进历史）。
两个镜像都需要先把对应的 deb 放到这里，再 `make build` / `make cli-build`。

## 取包

```bash
./scripts/fetch-client-deb.sh gui   # 图形端（海光麒麟 / amd64）
./scripts/fetch-client-deb.sh cli   # 命令行端（Ubuntu）
```

或手动从官方下载站取：
<https://sdwanapp.qianxin.com/download.html?product-type=sdwan>

## 期望的文件名与版本

| 文件 | 版本 | 校验 |
|---|---|---|
| `KYLIN-X86_SDWANClient_Setup.deb` | `sslvpnclient 1.1.3.1010701`（amd64） | md5 `49e3472a779e62be596117e4cefaee4a` |
| `Ubuntu_SDWANClient_Setup.deb` | `sslvpnclient 1.1.2.x`（amd64，CLI） | 见下载页 `MD5` 字段 |

## 说明

- 安装包版权归厂商所有，本项目只描述如何获取与安装，不重新分发。
- 图形端包是 linuxdeployqt 打包的 Qt5 应用，自带 Qt 与字体，解包后落在 `/opt/sslvpnclient`。
