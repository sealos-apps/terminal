# Sealos TTY Bridge

This directory contains the WebSocket-to-Kubernetes `pods/exec` bridge used by
the Terminal application's `/exec` workflow.

## Runtime boundary

The bridge is an independent Node.js runtime in the same repository and Helm
release as the frontend and controller. Next.js remains HTTP-only; browsers
connect to the bridge's public WSS origin and the bridge opens a Kubernetes PTY
using the authenticated user's kubeconfig.

The root `deploy/charts/terminal` chart owns deployment. The upstream bridge
chart, standalone release workflow, and Docker Compose configuration are not
duplicated here.

## Local development

```bash
pnpm install --frozen-lockfile
cp config.example.json config.json
pnpm dev
```

The example service listens on `http://localhost:3001` so it can run alongside
the frontend's default `http://localhost:3000` origin. `GET /healthz` and `GET /`
return a JSON health response. The WebSocket endpoint is `GET /exec`.

The example leaves `KUBE_API_SERVER` unset, so the bridge uses the server from
the kubeconfig supplied by each WebSocket client. Set it only when the bridge
must override that server, or use the Helm chart's `kubeApiServer: auto` for an
in-cluster deployment.

## Checks

```bash
pnpm test
pnpm check
```

`config.json` is local-only. It can contain cluster connection settings and
must never be committed or written to logs.
