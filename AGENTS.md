# Sealos Terminal Local Guidance

## Scope

This repository owns the standalone Sealos Terminal frontend and the Terminal
CRD controller. It is an application repository with two runtime units and one
unified deployable unit.

## Structure

- `frontend/`: Next.js pages, `/api/apply`, and `/exec`.
- `controller/`: Go controller, `Terminal` CRD, RBAC, and health endpoints.
- `deploy/`: unified Sealos bundle and Helm chart for frontend and controller.
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

The unified Helm chart must pass `helm lint` and an HTTP-mode `helm template`
render.

## Deployment Rules

- Runtime and cluster images use the public `ghcr.io/sealos-apps/terminal`
  namespaces described in `docs/runbook.md`.
- Build and publish `linux/amd64` by default. ARM64 is opt-in in the manual
  workflow.
- CI cluster archives use repository variable `OSS_BUCKET` and secrets
  `OSS_ENDPOINT`, `OSS_ACCESS_KEY_ID`, and `OSS_ACCESS_KEY_SECRET`; missing OSS
  configuration must fail the publishing job.
- Manual publishing runs must target `main` or a `v*` tag; archive filenames
  replace `/` in tag names with `-` while the OSS release prefix keeps the
  original tag.
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
