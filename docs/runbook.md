# Terminal Deployment Runbook

## Runtime Images

The public runtime image names are:

- `ghcr.io/sealos-apps/terminal/terminal-frontend`
- `ghcr.io/sealos-apps/terminal/terminal-controller`
- `ghcr.io/sealos-apps/terminal/terminal-cluster`

The GitHub Actions workflow always builds both `linux/amd64` on the native
`ubuntu-24.04` runner and `linux/arm64` on the native `ubuntu-24.04-arm` runner
for publishing. Main pushes use `sha-<7-char-sha>` image tags. Version tags use
their `v*` tag, and only version tags update `latest`. Both cases publish
multi-architecture manifests. The workflow does not use QEMU or buildx for
cross-architecture compilation.

## Cluster Image Bundle

Frontend and controller are installed together by one Sealos bundle:

```bash
make terminal-deploy-bundle
```

The bundle uses `deploy/entrypoint.sh`, sources
`/root/.sealos/cloud/scripts/tools.sh`, reads runtime values from
`sealos-system/sealos-config` and `cert-config`, and passes them to Helm.
User overrides are loaded in stable filename order from:

```text
/root/.sealos/cloud/values/apps/terminal/*-values.yaml
```

The release name is `terminal` and the namespace is `terminal-system`. During
migration, the entrypoint backs up and removes the old frontend release and
legacy controller release before installing the unified chart. The Terminal
CRD and existing Terminal CRs are retained. When the unified values directory
has no values file, the entrypoint migrates legacy values when available or
copies `terminal-values.yaml` from the chart.

## HTTP and Certificates

The frontend chart supports both HTTP and HTTPS. `disableHttps`, domain, ports,
and certificate name are injected from the platform configuration. HTTPS
Ingress TLS is omitted when `disableHttps=true`.

`CERT_MODE=https|acme|acmedns` sets
`platform.tlsRejectUnauthorized=0`; other or missing certificate modes use
`1`. The frontend container receives the result as
`NODE_TLS_REJECT_UNAUTHORIZED`.

## Application Terminal

Set the bridge base URL in the frontend chart values:

```yaml
frontend:
  terminalConfig:
    ttyAgentBaseUrl: https://tty-bridge.example.com
```

The value is injected as `TTY_AGENT_BASE_URL`. An empty value intentionally
causes `/exec` to show a configuration error instead of connecting to the
Terminal frontend or guessing a bridge address.

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
oss://<OSS_BUCKET>/ci/main/<7-char-sha>/terminal-cluster-main-<7-char-sha>-<arch>.tar.gz
```

Version tags use the release path:

```text
oss://<OSS_BUCKET>/release/<tag>/terminal-cluster-<tag>-<7-char-sha>-<arch>.tar.gz
```

When a tag contains `/`, the workflow replaces `/` with `-` in archive
filenames while preserving the original tag in the OSS release prefix.

Every architecture archive has a matching `.md5` file, so a complete upload
contains two archives and two checksums. Pushes to `main` and `v*` tags upload
both architectures automatically. A manual run with `upload_oss=true` also
enables the image publishing prerequisites and publishes both architectures.
Manual runs that publish images or upload OSS must target `main` or a `v*` tag;
publishing from another branch fails before the publishing jobs run.
Missing OSS configuration or an incomplete artifact set fails the upload job
instead of producing a green run without packages.

Publishing fails when either architecture build or archive is missing instead
of producing a partial release. Runtime and cluster images are built on the
native ARM64 runner, and manifests are combined with Docker's native
`docker manifest` commands.
