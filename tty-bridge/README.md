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

The service listens on `http://localhost:3000` by default. `GET /healthz` and
`GET /` return a JSON health response. The WebSocket endpoint is `GET /exec`.

## Checks

```bash
pnpm test
pnpm check
```

`config.json` is local-only. It can contain cluster connection settings and
must never be committed or written to logs.
