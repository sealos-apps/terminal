# Product

## Register

product

## Users

Sealos Cloud users open the standalone Terminal to inspect and operate their
workspace. Application users open a terminal from an application page to work
inside an existing Pod, with the target namespace, Pod, container, and optional
command supplied by the owning application.

The primary context is an active operational task. Users need a shell that
starts quickly, occupies the available viewport, preserves keyboard focus, and
makes connection failure or session exit obvious.

## Product Purpose

Sealos Terminal provides two terminal entry points behind one unified
deployable product. The product contains three runtime units:

1. The direct `/` workflow creates a short-lived Terminal workload and embeds
   its ttyd session.
2. The application `/exec` workflow connects to an existing workload through
   the repository's independent `tty-bridge` runtime and Kubernetes `pods/exec`.

Success means a user can reach the intended shell without understanding the
controller or bridge internals, while operators can deploy, upgrade, health
check, and roll back the frontend, tty-bridge, and controller together through
one release.

## Brand Personality

Direct, calm, operational.

The product should feel like a reliable work surface: quiet enough for long
sessions, explicit when a dependency is missing, and focused on the shell
rather than on product promotion.

## Anti-references

- Do not turn the product into a marketing landing page or add hero content
  around the terminal.
- Do not use decorative dashboard cards, excessive rounded containers, or
  ornamental gradients that compete with terminal output.
- Do not hide the active target, connection state, or recovery action.
- Do not guess a bridge URL or silently fall back to the frontend URL.
- Do not blur the ownership boundary between this repository, the bridge, and
  the Sealos main repository.

## Design Principles

1. **Put the shell first.** The terminal canvas gets the viewport and the
   user's keyboard focus.
2. **Separate the two workflows.** Direct Terminal lifecycle and application
   Pod exec have different owners and failure modes; their UI and deployment
   contracts must stay explicit.
3. **Make configuration observable.** Missing bridge configuration, ended
   sessions, and connection errors must produce a visible state with a clear
   recovery path.
4. **Prefer platform-native delivery.** Helm values, health probes, runtime
   images, cluster bundles, and Sealos values loading are part of the product,
   not afterthoughts.
5. **Keep operational state recoverable.** Reconnect, resize, clean shutdown,
   and resource backup behavior should be predictable under normal failures.

## Accessibility & Inclusion

The target is keyboard-first operation with readable contrast on the dark
terminal surface. Focus must remain usable for buttons and recovery actions,
error and session-ended states must not rely on color alone, and terminal
resizing must not hide content. Any future motion should honor
`prefers-reduced-motion`. User-visible copy should remain short and direct so
it can be scanned inside a full-screen tool.
