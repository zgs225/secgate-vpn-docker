SERVICE := secgate-gui
IMAGE   := $(or $(SECGATE_IMAGE),ghcr.io/zgs225/secgate-vpn-docker:latest)
GUI     := /opt/sslvpnclient/files/bin/sslvpn
URL     := http://127.0.0.1:6080/vnc.html

.PHONY: help build pull up down restart ps logs url shot verify smoke shell window ruleset nas-deploy fetch fetch-all rebuild multiarch clean

help: ## 显示所有可用命令
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

build: ## 本地构建镜像（按本机架构选 vendor/ 里的 deb，打 ghcr 同名 tag）
	docker compose build

pull: ## 拉取 GitHub Actions 发布到 GHCR 的镜像（不想本地构建时用它）
	docker compose pull $(SERVICE)

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

smoke: ## 运行时冒烟：临时起容器确认 X/noVNC/SOCKS/GUI 都活着（不登录）
	@./scripts/smoke-image.sh $(IMAGE)

ruleset: ## 导出 tun0 路由为 clash ipcidr ruleset（需已登录）
	@./scripts/export-clash-ruleset.sh

fetch: ## 取本机架构的厂商 deb 到 vendor/（不入库）
	@./scripts/fetch-client-deb.sh

fetch-all: ## 取 amd64 + arm64 两个 deb（多架构构建用）
	@./scripts/fetch-client-deb.sh all

multiarch: ## 本地构建 amd64+arm64 并推送（需先 docker login；平时交给 CI）
	docker buildx build --platform linux/amd64,linux/arm64 -t $(IMAGE) \
	  --build-arg IMAGE_VERSION=$$(git rev-parse --short HEAD) --push .

nas-deploy: ## 部署/更新到 NAS（NAS_HOST=...，端口可用 SOCKS_PORT/VNC_PORT 覆盖）
	@./scripts/deploy-nas.sh

shell: ## 进入容器
	docker exec -it $(SERVICE) bash

clean: ## 停容器并删除本地镜像
	docker compose down
	docker rmi $(IMAGE) 2>/dev/null || true
