SHELL := /usr/bin/env bash

PLATFORM ?= linux/amd64
FRONTEND_IMAGE ?= ghcr.io/sealos-apps/terminal/runtime/frontend:latest
CONTROLLER_IMAGE ?= ghcr.io/sealos-apps/terminal/runtime/controller:latest
SEALOS_FRONTEND_IMAGE ?= ghcr.io/sealos-apps/terminal/cluster/frontend:latest
SEALOS_CONTROLLER_IMAGE ?= ghcr.io/sealos-apps/terminal/cluster/controller:latest

.PHONY: frontend-install frontend-test frontend-build controller-test controller-build \
	helm-lint helm-template frontend-image frontend-image-push controller-image \
	controller-image-push frontend-deploy-bundle controller-deploy-bundle ci

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
	helm lint frontend/deploy/charts/terminal-frontend
	helm lint controller/deploy/charts/terminal-controller

helm-template:
	helm template terminal-frontend frontend/deploy/charts/terminal-frontend \
		--namespace terminal-frontend \
		--set-string terminalConfig.ttyAgentBaseUrl=https://tty-bridge.example.com >/dev/null
	helm template terminal controller/deploy/charts/terminal-controller \
		--namespace terminal-system >/dev/null

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

frontend-deploy-bundle:
	cd frontend/deploy && sealos build -t $(SEALOS_FRONTEND_IMAGE) -f Kubefile .

controller-deploy-bundle:
	cd controller/deploy && sealos build -t $(SEALOS_CONTROLLER_IMAGE) -f Kubefile .

ci: frontend-test frontend-build controller-test controller-build helm-lint helm-template
