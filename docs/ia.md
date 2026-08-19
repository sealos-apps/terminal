# Information Architecture

## Surface Map

```text
Terminal frontend
├── /                 Direct Terminal entry
│   ├── /api/apply    Create or reuse the user's Terminal CR
│   └── embedded ttyd session
├── /exec             Application Pod exec entry
│   ├── /api/env      Runtime configuration, including TTY_AGENT_BASE_URL
│   └── xterm session via sealos-tty-bridge
├── /healthz          Frontend health endpoint
└── /error            Generic error surface

Terminal controller
├── Terminal CRD      Desired direct-session state
├── Deployment        Temporary ttyd workload
├── Service           Temporary ttyd service
├── Ingress           Temporary user-facing terminal URL
├── /healthz          Controller liveness endpoint
└── /readyz           Controller readiness endpoint
```

## Entry Points

### Direct Terminal: `/`

The user enters the full-screen Terminal page. The frontend calls
`/api/apply`, which authenticates the current session, derives the user's
default namespace, and creates or reuses a `Terminal` resource. The page then
renders the returned domain in an iframe. The direct session supports multiple
tabs and forwards the current namespace and optional command to the ttyd
iframe.

### Application Terminal: `/exec`

An owning application opens `/exec` with query parameters:

- `ns` or `namespace`: target Kubernetes namespace, required.
- `pod`: target Pod name, required.
- `container`: target container, optional.
- `command` or `cmd`: one command string or a JSON/string array, optional.

The page reads `TTY_AGENT_BASE_URL` from `/api/env`, obtains the current
session kubeconfig, and mounts the xterm runtime. The runtime connects to the
external bridge, forwards stdin and resize events, renders stdout, and exposes
retry behavior when the stream ends or fails.

## Component Ownership

- `src/pages/index.tsx`: direct Terminal page and apply lifecycle.
- `src/components/terminal/`: direct-session tabs and ttyd iframes.
- `src/pages/exec.tsx`: application entry parsing and bridge configuration
  guard.
- `src/components/exec-terminal/`: target label, connection states, xterm,
  stdin/stdout, resize, and reconnect behavior.
- `src/pages/api/apply.ts`: direct Terminal CR creation/reuse API.
- `src/pages/api/env.ts`: safe runtime environment projection.

## Navigation Model

There is no product-wide navigation shell. The Terminal frontend is a focused
tool surface launched directly or embedded by another Sealos application. The
only in-surface navigation is the direct-session tab list and the retry action
for ended or failed `/exec` sessions.

## State Model

The `/exec` runtime uses these visible phases:

`idle` -> `connecting` -> `started` -> `ended`

Any connection or stream failure enters `error`. Both `ended` and `error`
expose a recovery action that starts a new connection. Missing required query
parameters and missing bridge configuration are handled before a WebSocket is
opened.

## Cross-Repository Navigation

Application buttons and their query construction remain in the Sealos main
repository. The bridge URL and WebSocket execution details remain in the
standalone `sealos-tty-bridge` service. Changes to those contracts must update
the owning repository and this document together.
