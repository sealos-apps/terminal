# Sealos Terminal Frontend

This Next.js application provides both Terminal workflows:

- `/`: creates a temporary Terminal workload through `/api/apply` and embeds its ttyd session.
- `/exec`: connects to an existing workload Pod through the independently deployed `sealos-tty-bridge`.

## Local development

```bash
pnpm install
pnpm dev
```

The `/exec` workflow requires `TTY_AGENT_BASE_URL` to point to the bridge base URL. The published TTY client adds the bridge execution path when opening the WebSocket.

## Build

```bash
pnpm test:ci
pnpm build
docker buildx build --platform linux/amd64 -t ghcr.io/sealos-apps/terminal/terminal-frontend:latest .
```
