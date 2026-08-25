## `@labring/sealos-tty-client`

Web Streams API client for `sealos-tty-bridge` (Kubernetes exec terminal over WebSocket).

### Install

```bash
pnpm add @labring/sealos-tty-client
```

### Browser + xterm (recommended)

```ts
import { connectTerminalStreams } from '@labring/sealos-tty-client'

const { stdout, stdin, resize } = await connectTerminalStreams({
	client: { baseUrl: 'http://localhost:3000' },
	connect: {
		kubeconfig,
		target: { namespace: 'default', pod: 'mypod', container: 'c1' },
		initialSize: { cols: term.cols, rows: term.rows },
	},
})

// stdin: xterm -> ws (binary)
const enc = new TextEncoder()
const writer = stdin.getWriter()
term.onData((d) => {
	void writer.write(enc.encode(d))
})
term.onResize(({ cols, rows }) => resize(cols, rows))

// stdout: ws -> xterm (binary -> text)
void stdout
	.pipeThrough(new TextDecoderStream())
	.pipeTo(new WritableStream({ write: s => term.write(s) }))
```

### Notes

- The server starts `exec` only after the **first** `resize`.
- By default the client sends `sealos-tty-v1` plus a URL-encoded kubeconfig-bearing subprotocol token (with the `urlencoded.kubeconfig.` prefix) during the WebSocket handshake.
- Set `connect.authInMessage = true` to send `{ type: 'auth', kubeconfig }` after the socket opens instead.
- Use `TextDecoderStream()` (or `TextDecoder(..., { stream: true })`) for UTF-8 across frames.
- In Node/SSR, inject `wsFactory` (e.g. `ws`) if `WebSocket` is missing.
