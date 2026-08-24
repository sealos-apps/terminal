# Terminal Architecture

This repository contains the standalone Terminal frontend and controller. The
`sealos-tty-bridge` service remains a separate deployment and is not copied
into this repository.

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
                    -> sealos-tty-bridge -> Kubernetes pods/exec
```

The direct path owns temporary Terminal resources through the `Terminal` CRD.
The application path does not create a Terminal CR. It requires
`TTY_AGENT_BASE_URL` to point to the separately deployed bridge base URL; the
published TTY client supplies the bridge execution path.

## Repository Boundaries

- `frontend/`: Next.js UI, `/api/apply`, `/exec`, and health endpoint.
- `controller/`: Go controller, CRD, RBAC, Helm chart, and health endpoints.
- `deploy/`: unified Sealos cluster image bundle and Helm chart for frontend and
  controller, installed in `terminal-system`.
- `sealos-tty-bridge`: external bridge service and its own deployment lifecycle.

The Sealos main repository remains the owner of application callers such as
Applaunchpad, DBProvider, and DevBox. This repository only provides the
Terminal-owned frontend and controller surfaces.
