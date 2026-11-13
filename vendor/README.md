# vendor/

厂商的图形客户端安装包**不入库**（开源仓库不转发第三方二进制，也避免几十 MB 的 blob
进历史）。构建前先把 deb 放到这里：

```bash
make fetch      # 本机架构那个
make fetch-all  # amd64 + arm64 都取（多架构构建/CI 用）
```

或手动从官方下载站取：
<https://sdwanapp.qianxin.com/download.html?product-type=sdwan>

## 期望的文件名与版本

厂商按架构发包，两个包结构完全一致（linuxdeployqt 打包的 Qt5 应用）：

| 文件 | 架构 | 版本 | 校验 |
|---|---|---|---|
| `KYLIN-X86_SDWANClient_Setup.deb` | amd64（「海光麒麟」） | `sslvpnclient 1.1.3.1010701` | md5 `49e3472a779e62be596117e4cefaee4a` |
| `KYLIN-ARM_SDWANClient_Setup.deb` | arm64（「鲲鹏麒麟」，飞腾同文件） | `sslvpnclient 1.1.5.1010901` | md5 `5d3ea8c60927bc902a166f14b6cbacd6` |

`make fetch` 只取本机架构那个，`make fetch-all` 两个都取。都会顺带写 `.sha256` 文件，
`make verify` 用它复核（sha256 文件同样不入库）。

## 说明

- 安装包版权归厂商所有，本项目只描述如何获取与安装，不重新分发。
- 两个包的客户端小版本不同（`1.1.3.1010701` vs `1.1.5.1010901`），厂商各自打包，不用强求对齐。
- 不想自己取包的话直接用预构建镜像：`docker pull ghcr.io/zgs225/secgate-vpn-docker:latest`
  （GitHub Actions 在 CI 里会自己跑 `make fetch` 取包并校验，见 `.github/workflows/docker.yml`）。
