SHELL := /usr/bin/env bash

PLATFORM ?= linux/amd64
FRONTEND_IMAGE ?= ghcr.io/sealos-apps/terminal/terminal-frontend:latest
CONTROLLER_IMAGE ?= ghcr.io/sealos-apps/terminal/terminal-controller:latest
TTY_BRIDGE_IMAGE ?= ghcr.io/sealos-apps/terminal/terminal-tty-bridge:latest
SEALOS_TERMINAL_IMAGE ?= ghcr.io/sealos-apps/terminal/terminal-cluster:latest

.PHONY: frontend-install frontend-test frontend-build controller-test controller-build \
	helm-lint helm-template frontend-image frontend-image-push controller-image \
	controller-image-push tty-bridge-install tty-bridge-check tty-bridge-image \
	tty-bridge-image-push terminal-deploy-bundle deploy-test ci

frontend-install:
	cd frontend && pnpm install --frozen-lockfile

frontend-test:
	cd frontend && pnpm test:ci

frontend-build:
	cd frontend && pnpm build

controller-test:
	$(MAKE) -C controller test

controller-build:
	$(MAKE) -C controller build TARGETARCH=amd64

tty-bridge-install:
	cd tty-bridge && corepack pnpm@9.15.9 install --frozen-lockfile

tty-bridge-check: tty-bridge-install
	cd tty-bridge && corepack pnpm@9.15.9 check

helm-lint:
	helm lint deploy/charts/terminal

helm-template:
	helm template terminal deploy/charts/terminal \
		--namespace terminal-system \
		--set-string frontend.terminalConfig.ttyAgentBaseUrl=https://tty-bridge.example.com >/dev/null
	helm template terminal deploy/charts/terminal \
		--namespace terminal-system \
		--set-string global.http.disableHttps=true \
		--set-string global.http.domain=terminal.example.com \
		--set-string global.http.httpPort=80 >/dev/null

deploy-test:
	bash deploy/test-entrypoint.sh

frontend-image:
	docker buildx build --platform=$(PLATFORM) --load \
		-t $(FRONTEND_IMAGE) -f frontend/Dockerfile frontend

frontend-image-push:
	docker buildx build --platform=$(PLATFORM) --push \
		-t $(FRONTEND_IMAGE) -f frontend/Dockerfile frontend

controller-image:
	$(MAKE) -C controller docker-build \
		IMG=$(CONTROLLER_IMAGE) PLATFORM=$(PLATFORM) TARGETARCH=amd64

controller-image-push: controller-build
	mv controller/bin/manager controller/bin/controller-terminal-amd64
	docker buildx build --platform=$(PLATFORM) --push \
		-t $(CONTROLLER_IMAGE) -f controller/Dockerfile controller \
		--build-arg TARGETARCH=amd64

tty-bridge-image:
	docker buildx build --platform=$(PLATFORM) --load \
		-t $(TTY_BRIDGE_IMAGE) -f tty-bridge/Dockerfile tty-bridge

tty-bridge-image-push:
	docker buildx build --platform=$(PLATFORM) --push \
		-t $(TTY_BRIDGE_IMAGE) -f tty-bridge/Dockerfile tty-bridge

terminal-deploy-bundle:
	cd deploy && sealos build -t $(SEALOS_TERMINAL_IMAGE) -f Kubefile .

ci: frontend-test frontend-build controller-test controller-build tty-bridge-check helm-lint helm-template deploy-test
