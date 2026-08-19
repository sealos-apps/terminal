# Sealos Terminal Local Guidance

## Scope

This repository owns the standalone Sealos Terminal frontend and the Terminal
CRD controller. It is an application repository with two independently
deployable units.

## Structure

- `frontend/`: Next.js pages, `/api/apply`, `/exec`, and the frontend Helm bundle.
- `controller/`: Go controller, `Terminal` CRD, RBAC, health endpoints, and the
  controller Helm bundle.
- `docs/`: architecture, information architecture, references, and operations.
- `PRODUCT.md`: product purpose, users, boundaries, and strategic principles.
- `DESIGN.md`: current frontend visual system and UI guardrails.
- `ROADMAP.md`: shipped baseline and follow-up work.

## Runtime Boundaries

- `/` uses `/api/apply`, creates a `Terminal` CR, and is reconciled by this
  repository's controller into a temporary Deployment, Service, and Ingress.
- `/exec` receives `namespace`, `pod`, optional `container`, and optional
  `command`. It uses `@labring/sealos-tty-client` and
  `TTY_AGENT_BASE_URL` to reach the separately deployed `sealos-tty-bridge`.
- Do not copy the bridge source into this repository. Do not move Applaunchpad,
  DBProvider, or DevBox callers here. Those callers remain in the Sealos main
  repository.

## Development Checks

Run from the repository root:

```bash
make frontend-install
make ci
```

Frontend-only checks run from `frontend/`:

```bash
pnpm test:ci
pnpm test:components:ci
pnpm lint
pnpm build
```

Controller checks run from `controller/`:

```bash
make test
make build TARGETARCH=amd64
```

Helm charts must pass `helm lint` and an HTTP-mode `helm template` render.

## Deployment Rules

- Runtime and cluster images use the public `ghcr.io/sealos-apps/terminal`
  namespaces described in `docs/runbook.md`.
- Build and publish `linux/amd64` by default. ARM64 is opt-in in the manual
  workflow.
- Keep `TTY_AGENT_BASE_URL` pointed at the bridge base URL, never at the
  Terminal frontend URL.
- Cluster bundles load app values through `/root/.sealos/cloud/values/apps/`
  and source `/root/.sealos/cloud/scripts/tools.sh`.
- Do not deploy to a cluster or modify a database as part of local verification
  unless the task explicitly authorizes that operation.

## Documentation Sources

Read `PRODUCT.md`, `DESIGN.md`, `docs/architecture.md`, and `docs/runbook.md`
before changing user-visible behavior or deployment contracts. Update the
corresponding reference or information-architecture document when a route,
environment variable, ownership boundary, or user workflow changes.
