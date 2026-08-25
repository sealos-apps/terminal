# Sealos Terminal

独立的 Sealos Terminal 仓库，包含三个运行单元和一个统一部署包：

- `frontend/`: Next.js Terminal 页面。
- `tty-bridge/`: WebSocket 到 Kubernetes `pods/exec` 的 Node 网关。
- `controller/`: `Terminal` CRD controller，负责直接打开 Terminal 时创建临时工作负载。
- `deploy/`: 同时部署 frontend、tty-bridge 和 controller 的统一 Helm chart 与 Sealos bundle。

## 两条终端链路

`/` 是旧的独立 Terminal 环境流程：前端调用 `/api/apply` 创建 `Terminal` CR，controller 创建临时 Deployment、Service 和 Ingress，前端嵌入 ttyd。

`/exec` 是应用内终端流程：调用方传入 namespace、Pod、container 和可选 command，前端通过 `@labring/sealos-tty-client` 连接同一 Helm release 中独立运行的 `tty-bridge`，bridge 再调用 Kubernetes `pods/exec`。Next.js 仍只负责 HTTP 页面，WebSocket 由 bridge 进程承载。

## 构建与校验

```bash
make frontend-install
make ci
make frontend-image PLATFORM=linux/amd64
make controller-image PLATFORM=linux/amd64
make tty-bridge-image PLATFORM=linux/amd64
```

本地镜像目标通过 `PLATFORM` 构建单一可加载镜像；生产发布默认构建并发布 `linux/amd64` 和 `linux/arm64`。手动工作流使用 `publish_images` 和 `upload_oss` 控制是否执行发布；手动选择 `publish_arm64=false` 时可仅发布 amd64 产物。

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

统一 Chart 会根据 frontend 和 tty-bridge 的 Ingress host、协议和端口自动生成 `TTY_AGENT_BASE_URL`，默认形如 `https://tty-bridge.<cloudDomain>`。同时 bridge 只允许精确的 frontend Origin 建立 WebSocket 连接。旧环境如仍使用外部 bridge，可通过 `frontend.terminalConfig.ttyAgentBaseUrl` 覆盖；为空时不需要手工配置。

## Sealos 部署包

```bash
make terminal-deploy-bundle
```

部署包使用 `deploy/charts/terminal` 统一 Helm chart 和 `deploy/entrypoint.sh`，在 `terminal-system` 中同时安装 frontend、tty-bridge 和 controller。迁移时会在安装新 release 前清理旧 frontend/controller release，并保留 Terminal CRD 与 Terminal CR。
