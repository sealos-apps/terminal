# Roadmap

## Current Baseline

The standalone repository is available on `main` with two independently
deployable units:

- `frontend/` provides direct Terminal (`/`) and application exec (`/exec`).
- `controller/` owns the `Terminal` CRD and direct-session resources.
- `sealos-tty-bridge` remains an external deployment used by `/exec`.
- Helm bundles, health probes, values loading, runtime images, cluster images,
  OSS archives, and amd64-first CI are included.

## Next

### Integrate Application Callers

Update the Sealos main repository's Applaunchpad, DBProvider, and DevBox
callers to use the standalone frontend `/exec` contract. This work belongs to
the Sealos main repository and is intentionally outside this repository.

### Deploy and Accept the Bridge Contract

Deploy `sealos-tty-bridge`, configure `terminalConfig.ttyAgentBaseUrl`, and
perform live acceptance for namespace, Pod, container, command, resize,
reconnect, authorization failure, and bridge-unavailable states.

### Expand Runtime Coverage

- Add focused frontend tests for `/exec` query parsing and missing bridge
  configuration.
- Add controller tests for HTTP mode, resource adoption, expiry, and health
  endpoints.
- Add an automated smoke path that checks both a direct Terminal session and an
  application Pod exec session in a disposable environment.

### Dependency and Release Hygiene

- Review GitHub Dependabot findings before the next release.
- Pin or document runtime image provenance and release version policy.
- Decide whether ARM64 should become a normal release target or remain manual.

## Later

- Add metrics for connection phases, bridge errors, and session duration.
- Document upgrade and rollback acceptance against a running Sealos cluster.
- Revisit shared frontend abstractions only when a second standalone app needs
  the same terminal runtime.

## Non-goals

- Copying `sealos-tty-bridge` source into this repository.
- Moving application callers out of the Sealos main repository.
- Replacing the direct `/` Terminal CRD workflow with `/exec`.
- Introducing database state into the standalone Terminal service.
