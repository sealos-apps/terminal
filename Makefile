SHELL := /usr/bin/env bash

PLATFORM ?= linux/amd64
FRONTEND_IMAGE ?= ghcr.io/sealos-apps/terminal/runtime/frontend:latest
CONTROLLER_IMAGE ?= ghcr.io/sealos-apps/terminal/runtime/controller:latest
SEALOS_TERMINAL_IMAGE ?= ghcr.io/sealos-apps/terminal/cluster/terminal:latest

.PHONY: frontend-install frontend-test frontend-build controller-test controller-build \
	helm-lint helm-template frontend-image frontend-image-push controller-image \
	controller-image-push terminal-deploy-bundle ci

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

terminal-deploy-bundle:
	cd deploy && sealos build -t $(SEALOS_TERMINAL_IMAGE) -f Kubefile .

ci: frontend-test frontend-build controller-test controller-build helm-lint helm-template
