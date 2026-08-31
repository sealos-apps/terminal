# Roadmap

## Current Baseline

The standalone repository is available on `main` with three runtime units and
one unified deployment unit:

- `frontend/` provides direct Terminal (`/`) and application exec (`/exec`).
- `tty-bridge/` owns the WebSocket-to-Kubernetes `pods/exec` gateway.
- `controller/` owns the `Terminal` CRD and direct-session resources.
- `deploy/` installs frontend, tty-bridge, and controller together through one
  Helm release in `terminal-system`.
- Helm bundles, health probes, automatic bridge URL and Origin configuration,
  values loading, runtime images, cluster images, and OSS archives are included.

## Next

### Integrate Application Callers

Update the Sealos main repository's Applaunchpad, DBProvider, and DevBox
callers to use the standalone frontend `/exec` contract. This work belongs to
the Sealos main repository and is intentionally outside this repository.

### Accept the Integrated Bridge Contract

Perform live acceptance for the integrated bridge: namespace, Pod, container,
command, resize, reconnect, authorization failure, Origin rejection, and
bridge-unavailable states.

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

## Later

- Add metrics for connection phases, bridge errors, and session duration.
- Document upgrade and rollback acceptance against a running Sealos cluster.
- Revisit shared frontend abstractions only when a second standalone app needs
  the same terminal runtime.

## Non-goals

- Moving application callers out of the Sealos main repository.
- Replacing the direct `/` Terminal CRD workflow with `/exec`.
- Introducing database state into the standalone Terminal service.
