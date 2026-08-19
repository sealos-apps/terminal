# Sealos Terminal

独立的 Sealos Terminal 仓库，包含两个运行单元：

- `frontend/`: Next.js Terminal 页面。
- `controller/`: `Terminal` CRD controller，负责直接打开 Terminal 时创建临时工作负载。

## 两条终端链路

`/` 是旧的独立 Terminal 环境流程：前端调用 `/api/apply` 创建 `Terminal` CR，controller 创建临时 Deployment、Service 和 Ingress，前端嵌入 ttyd。

`/exec` 是应用内终端流程：调用方传入 namespace、Pod、container 和可选 command，前端通过 `@labring/sealos-tty-client` 连接独立部署的 `sealos-tty-bridge`，bridge 再调用 Kubernetes `pods/exec`。bridge 源码和部署不放进本仓库。

## 构建与校验

```bash
make frontend-install
make ci
make frontend-image PLATFORM=linux/amd64
make controller-image PLATFORM=linux/amd64
```

默认只构建 `linux/amd64`。发布镜像时使用 `frontend-image-push` 和 `controller-image-push`，并先配置有权限的镜像仓库。

更完整的部署和发布说明见 [`docs/architecture.md`](docs/architecture.md) 和 [`docs/runbook.md`](docs/runbook.md)。GitHub Actions 默认发布 amd64；只有手动工作流显式打开 `publish_arm64` 时才增加 arm64。

## 项目文档

- [`PRODUCT.md`](PRODUCT.md)：产品目标、用户、边界和设计原则。
- [`DESIGN.md`](DESIGN.md)：当前终端界面的视觉系统和 UI 约束。
- [`ROADMAP.md`](ROADMAP.md)：已交付基线和后续工作。
- [`docs/architecture.md`](docs/architecture.md)：运行时链路和仓库边界。
- [`docs/ia.md`](docs/ia.md)：路由、组件归属和状态模型。
- [`docs/references.md`](docs/references.md)：外部服务、npm 包和代码事实来源。
- [`docs/runbook.md`](docs/runbook.md)：部署、发布和运维操作。

## `/exec` 配置

部署 frontend 时设置：

```yaml
terminalConfig:
  ttyAgentBaseUrl: https://tty-bridge.example.com
```

这会注入前端运行时环境变量 `TTY_AGENT_BASE_URL`。它必须指向 `sealos-tty-bridge` 的可访问 base URL，不能填 Terminal 前端自身地址。frontend 的 `/exec` 页面在配置为空时会直接显示配置错误，不会建立错误的 WebSocket 连接。

## Sealos 部署包

```bash
make frontend-deploy-bundle
make controller-deploy-bundle
```

两个部署包各自使用自己的 Helm chart 和 entrypoint，可独立升级和回滚；controller 的升级 entrypoint 会在 Helm 升级前备份现有资源。
