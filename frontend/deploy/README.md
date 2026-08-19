# Terminal frontend deployment

The frontend deployment bundle contains the Helm chart and the entrypoint used by Sealos:

```bash
sealos build -t ghcr.io/sealos-apps/terminal/cluster/frontend:latest -f Kubefile .
sealos run ghcr.io/sealos-apps/terminal/cluster/frontend:latest
```

The entrypoint installs or upgrades the `terminal-frontend` Helm release, adopts compatible existing resources, and auto-detects the Sealos cloud domain from `sealos-system/sealos-config`.

Set `TTY_AGENT_BASE_URL` or `terminalConfig.ttyAgentBaseUrl` to the base URL of the separately deployed `sealos-tty-bridge` when the `/exec` workflow is enabled. The chart injects this value into the Next.js runtime as `TTY_AGENT_BASE_URL`.

The frontend exposes `/healthz` for startup, readiness and liveness probes.
