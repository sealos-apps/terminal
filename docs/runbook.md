# Terminal Deployment Runbook

## Runtime Images

The public runtime image names are:

- `ghcr.io/sealos-apps/terminal/runtime/frontend`
- `ghcr.io/sealos-apps/terminal/runtime/controller`

The GitHub Actions workflow builds `linux/amd64` by default. A manual
workflow run can enable `publish_arm64` to add `linux/arm64` and publish the
multi-architecture manifests.

## Cluster Image Bundles

Each component has an independent Sealos bundle:

```bash
make frontend-deploy-bundle
make controller-deploy-bundle
```

The bundle entrypoint sources
`/root/.sealos/cloud/scripts/tools.sh`, reads runtime values from
`sealos-system/sealos-config` and `cert-config`, and passes them to Helm.
User overrides are loaded in stable filename order from:

```text
/root/.sealos/cloud/values/apps/terminal-frontend/*-values.yaml
/root/.sealos/cloud/values/apps/terminal-controller/*-values.yaml
```

When an app directory has no values file, the entrypoint logs a warning and
copies the chart's default `<name>-values.yaml` before installing or upgrading
the Helm release.

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
terminalConfig:
  ttyAgentBaseUrl: https://tty-bridge.example.com
```

The value is injected as `TTY_AGENT_BASE_URL`. An empty value intentionally
causes `/exec` to show a configuration error instead of connecting to the
Terminal frontend or guessing a bridge address.

## CI Archive Upload

On a publishing workflow run, cluster images are exported as `.tar.gz` files
with adjacent `.md5` files. The optional `upload_oss` input enables OSS upload
when these repository secrets are configured:

- `OSS_BUCKET_URL`
- `OSSUTIL_ENDPOINT`
- `OSS_ACCESS_KEY_ID`
- `OSS_ACCESS_KEY_SECRET`

The workflow never requires an ARM publish for the default amd64 release path.
