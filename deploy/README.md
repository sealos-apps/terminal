# Sealos Terminal deployment

The deployment bundle contains one Helm chart for both the Terminal frontend
and controller. Both runtime components are installed by one release in the
`terminal-system` namespace.

```bash
sealos build -t ghcr.io/sealos-apps/terminal/cluster/terminal:latest -f Kubefile .
sealos run ghcr.io/sealos-apps/terminal/cluster/terminal:latest
```

The bundle entrypoint is `entrypoint.sh`. During migration it removes the old
`terminal-frontend` release and the old controller release before installing
the unified `terminal` release. The Terminal CRD and existing `Terminal` CRs
are retained.

Runtime values are loaded from:

```text
/root/.sealos/cloud/values/apps/terminal/*-values.yaml
```

If only the legacy `terminal-frontend` and `terminal-controller` values
directories exist, the entrypoint maps their values into the unified schema.
Set `frontend.terminalConfig.ttyAgentBaseUrl` or `TTY_AGENT_BASE_URL` to the
base URL of the separately deployed `sealos-tty-bridge` when `/exec` is used.
