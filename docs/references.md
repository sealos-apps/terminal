# References

This file records the external systems and local source-of-truth files that
define the Terminal contract.

## Local Sources of Truth

| Topic | Source |
| --- | --- |
| Product purpose and boundaries | [`PRODUCT.md`](../PRODUCT.md) |
| Visual system and UI guardrails | [`DESIGN.md`](../DESIGN.md) |
| Runtime architecture | [`architecture.md`](architecture.md) |
| Routes and component ownership | [`ia.md`](ia.md) |
| Deployment and release operations | [`runbook.md`](runbook.md) |
| Local agent rules | [`AGENTS.md`](../AGENTS.md) |
| Frontend package contract | [`frontend/package.json`](../frontend/package.json) |
| Unified deployment values | [`deploy/charts/terminal/values.yaml`](../deploy/charts/terminal/values.yaml) |
| Controller API and CRD | [`controller/api/v1/terminal_types.go`](../controller/api/v1/terminal_types.go) |

## Sealos Repositories and Services

- [Sealos main](https://github.com/labring/sealos): owns application callers
  such as Applaunchpad, DBProvider, and DevBox.
- [sealos-tty-bridge](https://github.com/labring-sigs/sealos-tty-bridge): owns
  the WebSocket-to-Kubernetes `pods/exec` bridge, its authentication and its
  deployment lifecycle.
- [sealos-apps/terminal](https://github.com/sealos-apps/terminal): this
  standalone repository.

## Published Packages

- [`@labring/sealos-shared-sdk`](https://www.npmjs.com/package/@labring/sealos-shared-sdk):
  shared frontend utilities and providers.
- [`@labring/sealos-desktop-sdk`](https://www.npmjs.com/package/@labring/sealos-desktop-sdk):
  Sealos desktop session and app integration types.
- [`@labring/sealos-tty-client`](https://www.npmjs.com/package/@labring/sealos-tty-client):
  frontend client used to open bridge terminal streams.

The frontend consumes published npm packages. It must not reintroduce local
workspace links for these dependencies without an explicit ownership decision.

## Platform References

- [Kubernetes `pods/exec` API](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_exec/)
- [Helm upgrade and install](https://helm.sh/docs/helm/helm_upgrade/)
- [Next.js Pages Router](https://nextjs.org/docs/pages)
- [xterm.js](https://xtermjs.org/)

## Contract Change Rule

When a change affects a route, query parameter, environment variable, bridge
path, CRD field, image name, or deployment values directory, update the local
source-of-truth document and the owning external repository documentation when
that repository is in scope.
