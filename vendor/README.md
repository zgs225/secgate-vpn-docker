# vendor/

厂商的图形客户端安装包**不入库**（开源仓库不转发第三方二进制，也避免几十 MB 的 blob
进历史）。构建前先把 deb 放到这里：

```bash
make fetch      # 等价于 ./scripts/fetch-client-deb.sh
```

或手动从官方下载站取：
<https://sdwanapp.qianxin.com/download.html?product-type=sdwan>

## 期望的文件名与版本

| 文件 | 版本 | 校验 |
|---|---|---|
| `KYLIN-X86_SDWANClient_Setup.deb` | `sslvpnclient 1.1.3.1010701`（amd64，「海光麒麟」GUI） | md5 `49e3472a779e62be596117e4cefaee4a` |

`make fetch` 会顺带写 `KYLIN-X86_SDWANClient_Setup.deb.sha256`，`make verify` 用它复核
（sha256 文件同样不入库）。

## 说明

- 安装包版权归厂商所有，本项目只描述如何获取与安装，不重新分发。
- 包是 linuxdeployqt 打包的 Qt5 应用，自带 Qt 与字体，解包后落在 `/opt/sslvpnclient`。
