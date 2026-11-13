SERVICE := secgate-gui
CLI_SERVICE := secgate-cli
IMAGE   := local/secgate-gui:1.1.3.1010701
GUI     := /opt/sslvpnclient/files/bin/sslvpn
CLI     := /opt/sslvpnclient/secgateaccess
URL     := http://127.0.0.1:6080/vnc.html

.PHONY: help build up down restart ps logs url shot verify shell window ruleset nas-deploy fetch cli-fetch cli-build cli-up cli-login cli-quick cli-info cli-stop-login cli-log rebuild clean

help: ## 显示所有可用命令
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

build: ## 构建图形端镜像（官方海光麒麟 deb）
	docker compose build

rebuild: ## 无缓存重建图形端镜像
	docker compose build --no-cache secgate-gui

up: ## 启动图形端容器
	docker compose up -d secgate-gui
	@sleep 2; docker compose ps; echo; echo "浏览器打开: $(URL)"

down: ## 停止并删除图形端容器
	docker compose down

restart: ## 重启图形端容器
	docker compose restart secgate-gui

ps: ## 查看容器状态
	docker compose ps

logs: ## 跟随容器内各服务日志（entrypoint/Xvfb/websockify）
	docker compose logs -f --tail=80 $(SERVICE)

url: ## 打印 noVNC 地址
	@echo $(URL)

shot: ## 截图当前桌面 → ./screenshots/（自检 GUI 是否正常渲染）
	@mkdir -p screenshots
	@docker exec $(SERVICE) scrot -o /tmp/screen.png
	@docker cp $(SERVICE):/tmp/screen.png screenshots/gui-$$(date +%H%M%S).png >/dev/null
	@ls -t screenshots/*.png | head -1

window: ## 列出 X 里的窗口（确认客户端窗口存在）
	@docker exec $(SERVICE) xwininfo -root -tree | head -30

verify: ## 自检：X / noVNC / SOCKS5 / 客户端进程 / 窗口 / 隧道
	@./scripts/verify.sh

ruleset: ## 导出 tun0 路由为 clash ipcidr ruleset（需已登录）
	@./scripts/export-clash-ruleset.sh

fetch: ## 从官方下载站取图形端安装包到 vendor/（不入库）
	@./scripts/fetch-client-deb.sh gui

cli-fetch: ## 取命令行端安装包到 vendor/
	@./scripts/fetch-client-deb.sh cli

nas-deploy: ## 部署/更新到 NAS（NAS_HOST=...，端口可用 SOCKS_PORT/VNC_PORT 覆盖）
	@./scripts/deploy-nas.sh

shell: ## 进入容器
	docker exec -it $(SERVICE) bash

# ---- 命令行版（不支持二次认证，仅作备用） ----
cli-build: ## 构建 CLI 镜像
	docker compose --profile cli build secgate-cli

cli-up: ## 启动 CLI 容器（SOCKS5 在 127.0.0.1:1081）
	docker compose --profile cli up -d secgate-cli

cli-login: ## CLI 手动登录
	docker exec -it $(CLI_SERVICE) $(CLI) nationconnect

cli-quick: ## CLI 用上次配置自动登录
	docker exec -it $(CLI_SERVICE) $(CLI) quickconnect

cli-info: ## CLI 查看隧道信息
	docker exec -it $(CLI_SERVICE) $(CLI) showinfo

cli-stop-login: ## 杀掉卡住的 CLI 登录进程
	docker exec $(CLI_SERVICE) pkill -f secgateaccess || true

cli-log: ## 跟随 CLI 客户端日志
	@docker exec $(CLI_SERVICE) tail -n +1 -f /opt/sslvpnclient/log/log.txt

clean: ## 停容器并删除本地镜像
	docker compose --profile cli down
	docker rmi $(IMAGE) local/secgate-cli:1.1.2.65051 2>/dev/null || true
