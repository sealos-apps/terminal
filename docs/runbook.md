# Terminal Deployment Runbook

## Runtime Images

The public runtime image names are:

- `ghcr.io/sealos-apps/terminal/terminal-frontend`
- `ghcr.io/sealos-apps/terminal/terminal-tty-bridge`
- `ghcr.io/sealos-apps/terminal/terminal-controller`
- `ghcr.io/sealos-apps/terminal/terminal-cluster`

Production publishing targets are `linux/amd64` and `linux/arm64`. The amd64
jobs use the native `ubuntu-24.04` runner. Main pushes use `sha-<7-char-sha>`
image tags. Version tags use their `v*` tag, and only version tags update
`latest`. Automatic and manual publishing always publish both architectures.

## Cluster Image Bundle

Frontend, tty-bridge, and controller are installed together by one Sealos bundle:

```bash
make terminal-deploy-bundle
```

The bundle uses `deploy/entrypoint.sh`, sources
`/root/.sealos/cloud/scripts/tools.sh`, reads runtime values from
`sealos-system/sealos-config` and `cert-config`, and passes them to Helm.
When present, the generated `terminal-values.yaml` is loaded first; additional
user overrides are then loaded in stable filename order from:

```text
/root/.sealos/cloud/values/apps/terminal/*-values.yaml
```

The release name is `terminal` and the namespace is `terminal-system`. During
migration, the entrypoint removes the old frontend release and a non-unified
`terminal` release before installing the unified chart. The Terminal CRD and
existing Terminal CRs are retained. Before preparing values, an upgrade from
an existing `terminal-0.1.0` chart removes only
`/root/.sealos/cloud/values/apps/terminal/terminal-values.yaml`. This
compatibility cleanup preserves all other user `*-values.yaml` overrides. If
it removes the only values file, the upgrade uses the chart's built-in defaults
without recreating that persistent file. In all other cases, an empty unified
values directory receives `terminal-values.yaml` from the chart.

## Helm Health Tests

`helm test terminal -n terminal-system` checks each runtime through its
cluster-internal health endpoint: frontend and tty-bridge use `/healthz`, while
the controller uses `/readyz` on its internal health Service at
`controller.service.health.port` (default `8081`).
The test does not expose a public Ingress health route or enable metrics.

## HTTP and Certificates

The frontend chart supports both HTTP and HTTPS. `disableHttps`, domain, ports,
and certificate name are injected from the platform configuration. HTTPS
Ingress TLS is omitted when `disableHttps=true`.

`CERT_MODE=https|acme|acmedns` sets
`platform.tlsRejectUnauthorized=0`; other or missing certificate modes use
`1`. The frontend container receives the result as
`NODE_TLS_REJECT_UNAUTHORIZED`.

## Application Terminal

The chart automatically derives the bridge base URL from the bridge Ingress and
injects it as `TTY_AGENT_BASE_URL`. With the default hosts this is
`https://tty-bridge.<cloudDomain>`, while the frontend Origin allowlist contains
only `https://terminal.<cloudDomain>`. HTTP mode derives matching `http://`
origins and omits TLS.

For migration from an independently deployed bridge, set
`frontend.terminalConfig.ttyAgentBaseUrl` or `TTY_AGENT_BASE_URL`; the override
is optional and must point to the bridge, never the Terminal frontend.

The bridge accepts the user's kubeconfig for each WebSocket session, validates
it, and performs `pods/exec` with that identity. Keep the bridge behind HTTPS/WSS
and do not log or persist kubeconfig contents.

## CI Archive Upload

On a publishing workflow run, the unified Terminal Sealos image is exported as
a versioned `.tar.gz` file with an adjacent `.md5` file. The archive version is
`${GITHUB_REF_NAME}-${SHORT_SHA}`, where `SHORT_SHA` is the first seven
characters of `GITHUB_SHA`. The `/` character is replaced with `-` in archive
filenames. GitHub
Artifacts only pass the files between workflow jobs; OSS is the distribution
source for offline cluster packages.

The repository variable `OSS_BUCKET` must contain the bucket and Terminal
artifact root, for example:

```text
<bucket>/offline/sealos-apps/terminal
```

Configure these repository secrets:

- `OSS_ENDPOINT`
- `OSS_ACCESS_KEY_ID`
- `OSS_ACCESS_KEY_SECRET`

Main branch packages are uploaded to:

```text
oss://<OSS_BUCKET>/ci/main/<7-char-sha>/terminal-cluster-main-<7-char-sha>-amd64.tar.gz
oss://<OSS_BUCKET>/ci/main/<7-char-sha>/terminal-cluster-main-<7-char-sha>-arm64.tar.gz
```

Version tags use the release path:

```text
oss://<OSS_BUCKET>/release/<tag>/terminal-cluster-<tag>-<7-char-sha>-amd64.tar.gz
oss://<OSS_BUCKET>/release/<tag>/terminal-cluster-<tag>-<7-char-sha>-arm64.tar.gz
```

When a tag contains `/`, the workflow replaces `/` with `-` in archive
filenames while preserving the original tag in the OSS release prefix.

Each architecture archive has a matching `.md5` file. A manual run with
`upload_oss=true` also enables the image publishing prerequisites. Every
publishing run requires and uploads both architecture archives and checksums.
Manual runs that publish images or upload OSS must target `main` or a `v*` tag;
publishing from another branch fails before the publishing jobs run.
Missing OSS configuration or an incomplete artifact set fails the upload job
instead of producing a green run without packages.

Publishing fails when a required architecture build or archive is missing
instead of producing a partial release. Runtime and cluster images are built on
native amd64 and arm64 runners.
