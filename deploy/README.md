# Sealos Terminal deployment

The deployment bundle contains one Helm chart for the Terminal frontend,
TTY bridge, and controller. All runtime components are installed by one release
in the `terminal-system` namespace.

```bash
sealos build -t ghcr.io/sealos-apps/terminal/terminal-cluster:latest -f Kubefile .
sealos run ghcr.io/sealos-apps/terminal/terminal-cluster:latest
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
The chart derives the public bridge URL and the exact frontend Origin allowlist
from the effective domain, ports, and Ingress hosts. `frontend.terminalConfig.ttyAgentBaseUrl`
and `TTY_AGENT_BASE_URL` remain optional compatibility overrides for an external
bridge; they are not required for the integrated runtime.
