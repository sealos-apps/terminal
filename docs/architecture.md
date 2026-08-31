# Terminal Architecture

This repository contains the standalone Terminal frontend, the independent
`tty-bridge` Node runtime, and the Terminal controller. They are installed by
one Helm release but remain separate processes and network services.

Product intent is documented in [`PRODUCT.md`](../PRODUCT.md), the current UI
system in [`DESIGN.md`](../DESIGN.md), and route ownership in [`ia.md`](ia.md).
Use [`references.md`](references.md) to trace external contracts and package
ownership.

## Runtime Paths

```text
Direct Terminal (/)
browser -> frontend /api/apply -> Terminal CR -> controller
         -> temporary Deployment/Service/Ingress -> ttyd

Application Terminal (/exec)
application button -> frontend /exec -> @labring/sealos-tty-client
                    -> tty-bridge WSS -> Kubernetes pods/exec
```

The direct path owns temporary Terminal resources through the `Terminal` CRD.
The application path does not create a Terminal CR. The unified chart derives
`TTY_AGENT_BASE_URL` from the bridge Ingress unless an external bridge override
is explicitly supplied. The published TTY client supplies the bridge execution
path.

## Repository Boundaries

- `frontend/`: Next.js UI, `/api/apply`, `/exec`, and health endpoint.
- `tty-bridge/`: Node HTTP/WebSocket gateway, kubeconfig validation, resize and
  stream handling, and Kubernetes `pods/exec`.
- `controller/`: Go controller, CRD, RBAC, Helm chart, and health endpoints.
- `deploy/`: unified Sealos cluster image bundle and Helm chart for frontend,
  tty-bridge, and controller, installed in `terminal-system`.

The Sealos main repository remains the owner of application callers such as
Applaunchpad, DBProvider, and DevBox. This repository provides the Terminal-owned
frontend, bridge, and controller surfaces.

The bridge still owns its WebSocket authentication boundary. It receives the
user kubeconfig for the session, validates it, and never relies on a broad
bridge ServiceAccount to access arbitrary Pods. HTTPS/WSS and the exact
frontend Origin allowlist remain required deployment properties.
