# Sealos Terminal deployment

The deployment bundle contains one Helm chart for the Terminal frontend,
TTY bridge, and controller. All runtime components are installed by one release
in the `terminal-system` namespace.

```bash
sealos build -t ghcr.io/sealos-apps/terminal/terminal-cluster:latest -f Kubefile .
sealos run ghcr.io/sealos-apps/terminal/terminal-cluster:latest
```

The bundle entrypoint is `entrypoint.sh`. During migration it removes the old
`terminal-frontend` release and a non-unified `terminal` release before
installing the unified `terminal` release. The Terminal CRD and existing
`Terminal` CRs are retained.

Runtime values are loaded from:

```text
/root/.sealos/cloud/values/apps/terminal/*-values.yaml
```

When upgrading an existing `terminal` release whose Helm chart is exactly
`terminal-0.1.0`, the entrypoint removes
`/root/.sealos/cloud/values/apps/terminal/terminal-values.yaml` before it
collects values. This one-time compatibility cleanup prevents the legacy
generated values from being passed to the current chart. It removes no other
file; additional `*-values.yaml` overrides remain in place. If that was the
only values file, the upgrade uses the chart's built-in defaults without
recreating the removed persistent file. Fresh installs and releases using any
other chart version continue with the normal values-loading behavior.

The chart derives the public bridge URL and the exact frontend Origin allowlist
from the effective domain, ports, and Ingress hosts. `frontend.terminalConfig.ttyAgentBaseUrl`
and `TTY_AGENT_BASE_URL` remain optional compatibility overrides for an external
bridge; they are not required for the integrated runtime.
