# Sealos Terminal

独立的 Sealos Terminal 仓库，包含两个运行单元和一个统一部署包：

- `frontend/`: Next.js Terminal 页面。
- `controller/`: `Terminal` CRD controller，负责直接打开 Terminal 时创建临时工作负载。
- `deploy/`: 同时部署 frontend 和 controller 的统一 Helm chart 与 Sealos bundle。

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

本地镜像目标通过 `PLATFORM` 构建单一可加载镜像；GitHub Actions 在 Push 到 `main` 或 `v*` tag 时固定构建并发布 amd64 和 arm64，并自动发布多架构 manifest 与 OSS 集群包。手动工作流使用 `publish_images` 和 `upload_oss` 控制是否执行发布。

更完整的部署和发布说明见 [`docs/architecture.md`](docs/architecture.md) 和 [`docs/runbook.md`](docs/runbook.md)。

GitHub Actions 会把统一的 Terminal Sealos 集群包上传到 OSS。`main` 使用 `ci/main/<7-char-sha>/`，`v*` tag 使用 `release/<tag>/`；集群包不作为 GitHub Release asset 发布。仓库变量为 `OSS_BUCKET`，仓库 secrets 为 `OSS_ENDPOINT`、`OSS_ACCESS_KEY_ID` 和 `OSS_ACCESS_KEY_SECRET`，具体路径配置见 [`docs/runbook.md`](docs/runbook.md#ci-archive-upload)。

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
frontend:
  terminalConfig:
    ttyAgentBaseUrl: https://tty-bridge.example.com
```

这会注入前端运行时环境变量 `TTY_AGENT_BASE_URL`。它必须指向 `sealos-tty-bridge` 的可访问 base URL，不能填 Terminal 前端自身地址。frontend 的 `/exec` 页面在配置为空时会直接显示配置错误，不会建立错误的 WebSocket 连接。

## Sealos 部署包

```bash
make terminal-deploy-bundle
```

部署包使用 `deploy/charts/terminal` 统一 Helm chart 和 `deploy/entrypoint.sh`，在 `terminal-system` 中同时安装 frontend 和 controller。迁移时会在安装新 release 前清理旧 frontend/controller release，并保留 Terminal CRD 与 Terminal CR。
