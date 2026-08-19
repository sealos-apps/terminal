---
name: Sealos Terminal
description: A full-screen Sealos terminal for direct shells and application Pod exec.
colors:
  terminal-surface: "#2b2b2b"
  terminal-surface-deep: "#1a1a1a"
  terminal-surface-hover: "#232323"
  terminal-divider: "#232528"
  terminal-text: "#ffffff"
  terminal-text-muted: "#cccccc"
  scrollbar-thumb: "#bfbfbf"
  scrollbar-thumb-hover: "#999999"
  overlay-scrim: "#00000059"
typography:
  terminal:
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.2
  label:
    fontFamily: "system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.4
  body:
    fontFamily: "system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.4
rounded:
  scrollbar: "6px"
spacing:
  sidebar: "200px"
  sidebar-mobile: "136px"
  compact: "8px"
  control: "12px"
  overlay: "24px"
components:
  terminal-canvas:
    backgroundColor: "{colors.terminal-surface}"
    textColor: "{colors.terminal-text}"
    rounded: "0"
    width: "100%"
    height: "100%"
  terminal-sidebar:
    backgroundColor: "{colors.terminal-surface-deep}"
    textColor: "{colors.terminal-text}"
    rounded: "0"
    width: "{spacing.sidebar}"
  terminal-tab-active:
    backgroundColor: "{colors.terminal-surface}"
    textColor: "{colors.terminal-text}"
    rounded: "0"
    padding: "12px 12px 12px 16px"
  recovery-button:
    backgroundColor: "{colors.terminal-text}"
    textColor: "{colors.terminal-surface-deep}"
    rounded: "4px"
    padding: "8px 12px"
---

# Design System: Sealos Terminal

## Overview

**Creative North Star: "The Cloud Shell"**

The interface is a work surface, not a destination page. A dark terminal
canvas fills the viewport, with only the controls needed to choose a direct
session, identify an application target, or recover a failed connection. The
visual language is quiet and dense enough for repeated operational use.

Depth comes from tonal layering rather than decoration: the sidebar is deeper
than the terminal canvas, active tabs return to the canvas tone, and transient
error or ended states use a restrained scrim. The system explicitly rejects
marketing hero layouts, decorative card grids, gradients, and ambiguous
connection states.

**Key Characteristics:**

- Full-screen terminal canvas.
- Dark neutral surfaces with white and muted-white text.
- Compact 12px labels and 14px monospace terminal output.
- Keyboard-first recovery and resize behavior.
- Flat surfaces with state-based overlays instead of ornamental shadows.

## Colors

The palette is restrained and terminal-native. The dark surface is the primary
visual field; lighter values exist for legibility and state feedback, not as
decoration.

### Primary

- **Terminal Surface** (`#2b2b2b`): Main canvas, xterm background, and active
  tab surface.
- **Terminal Text** (`#ffffff`): Terminal output, primary labels, and recovery
  content.

### Neutral

- **Sidebar Surface** (`#1a1a1a`): Direct Terminal session list and add-session
  control area.
- **Hover Surface** (`#232323`): Sidebar hover state.
- **Divider** (`#232528`): Sidebar header bottom border.
- **Muted Text** (`rgba(255, 255, 255, 0.7-0.9)`): Metadata, target labels, and
  secondary state copy.
- **Overlay Scrim** (`rgba(0, 0, 0, 0.35)`): Error and ended-session overlays.
- **Scrollbar Thumb** (`#bfbfbf`, hover `#999999`): The global scrollbar only.

### Named Rules

**The Shell Is the Accent Rule.** Do not introduce a competing brand accent on
the terminal surface. State should be communicated through copy, focus, and
the existing neutral contrast system.

## Typography

**Display Font:** None. The product has no marketing display surface.

**Body Font:** The Chakra/system UI stack inherited by the application.

**Label/Mono Font:** `ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas,
'Liberation Mono', 'Courier New', monospace` for xterm output and terminal
target labels.

**Character:** Compact, legible, and utilitarian. Terminal output must remain
monospace; surrounding status copy should stay small enough to preserve the
shell as the dominant content.

### Hierarchy

- **Terminal** (400, 14px, 1.2): xterm output and user input surface.
- **Body** (400, 14px, 1.4): General status or configuration copy.
- **Label** (400, 12px, 1.4): Active target, tab labels, and transient status.
- **Error/Recovery label** (Chakra `sm`/`xs`): Short state title, detail, and
  action inside the overlay.

### Named Rules

**The Readable Shell Rule.** Never reduce terminal output below 14px or use a
proportional font for command output. Keep transient copy short instead of
shrinking it until it competes with the shell.

## Elevation

The system is flat by default. It uses tonal layering between the sidebar and
canvas, plus a 35% black scrim for error and ended-session states. There is no
general card shadow vocabulary and no decorative elevation hierarchy.

### Named Rules

**The Flat-By-Default Rule.** Add elevation only when it clarifies a transient
state or keeps a control readable over terminal output. Do not add broad soft
shadows to ordinary controls or containers.

## Components

### Terminal Canvas

- **Shape:** Full viewport, square corners (`0`).
- **Background:** `#2b2b2b`.
- **Text:** White terminal output with xterm's own rendering.
- **Behavior:** Fit to the available container and send remote resize events.

### Direct Terminal Sidebar

- **Shape:** Fixed 200px desktop width, 136px at widths below 768px.
- **Background:** `#1a1a1a`; no shadow.
- **Header:** 50px high, 16px left padding, 2px `#232528` bottom divider.
- **Interaction:** Hover uses `#232323`; the add-session control is always
  visible.

### Terminal Tab

- **Shape:** Flat row with 12px vertical padding and 16px left padding.
- **Active:** Returns to `#2b2b2b` so the selected session joins the canvas.
- **Inactive:** Transparent against the sidebar, `#232323` on hover.
- **Actions:** The close icon appears on hover and remains visible for the
  active tab. The last remaining tab cannot be deleted.

### Application Exec Header

- **Shape:** Non-interactive overlay label at 10px top and 12px left.
- **Typography:** 12px, muted white, no background panel.
- **Content:** `namespace/pod:container` target identity.

### Recovery Overlay

- **Shape:** Full viewport overlay with 24px padding and a 35% black scrim.
- **Content:** Short state title, optional detail, and a visible reconnect or
  retry action.
- **Behavior:** The action increments the retry sequence and starts a fresh
  connection. Keyboard Enter is also supported after the session ends or fails.

### Focus and Motion

- Keep interactive controls keyboard reachable and preserve visible focus.
- Do not animate the terminal canvas or output. Loading may use the existing
  Chakra spinner; future transitions must honor `prefers-reduced-motion`.

## Do's and Don'ts

### Do:

- **Do** keep the terminal canvas full-screen and visually dominant.
- **Do** use the existing `#2b2b2b`, `#1a1a1a`, and `#232323` surface roles.
- **Do** identify the active application target in a compact label.
- **Do** give ended and failed sessions a visible recovery action.
- **Do** preserve keyboard input, resize behavior, and readable monospace
  output.
- **Do** keep bridge configuration errors explicit.

### Don't:

- **Don't** add a marketing hero or promotional content around the terminal.
- **Don't** use decorative dashboard cards, ornamental gradients, or broad
  soft shadows.
- **Don't** hide the active target, connection state, or recovery action.
- **Don't** guess a bridge URL or connect to the frontend as a fallback.
- **Don't** use a proportional font for terminal output.
- **Don't** use color alone to communicate error, ended, or disconnected state.
