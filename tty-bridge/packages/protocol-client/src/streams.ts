import type { ServerFrame } from './protocol.js'
import type { WsCloseEvent, WsFactory, WsLike } from './types.js'
import {
	encodeKubeconfigSubprotocol,
	safeJsonStringify,
	toErrorMessage,
	TTY_WS_SUBPROTOCOL,
} from './protocol.js'

export type TerminalStreams = {
	/**
	 * Session state transitions.
	 */
	state: ReadableStream<TerminalSessionState>
	/**
	 * JSON control frames from server (ready/authed/started/status/error/pong).
	 */
	frames: ReadableStream<ServerFrame>
	/**
	 * Binary stdout/stderr bytes from server.
	 */
	stdout: ReadableStream<Uint8Array>
	/**
	 * Binary stdin bytes to server.
	 */
	stdin: WritableStream<Uint8Array>
	/**
	 * Resize terminal. The first resize triggers exec start on server-side.
	 */
	resize: (cols: number, rows: number) => void
	/**
	 * Close the underlying websocket.
	 */
	close: (code?: number, reason?: string) => void
}

export type ConnectTerminalStreamsOptions = {
	client: ProtocolClientOptions
	connect: TerminalSessionConnectOptions
	/**
	 * Abort the connection and close streams.
	 */
	signal?: AbortSignal
}

type Ctrl<T> = ReadableStreamDefaultController<T>

function tryClose<T>(c: Ctrl<T> | null | undefined): void {
	try {
		c?.close()
	}
	catch {}
}

function tryError<T>(c: Ctrl<T> | null | undefined, err: unknown): void {
	try {
		c?.error(err)
	}
	catch {}
}

/**
 * Connect and expose a Web Streams API interface.
 *
 * Design notes:
 * - stdout is a binary stream (Uint8Array). For xterm, you usually want:
 *   `stdout.pipeThrough(new TextDecoderStream()).pipeTo(...)`.
 * - stdin is a binary WritableStream. For xterm:
 *   `term.onData(d => writer.write(new TextEncoder().encode(d)))`.
 */
export type ExecTarget = {
	namespace: string
	pod: string
	container?: string
	command?: string[]
}

export type ProtocolClientOptions = {
	baseUrl: string
	/**
	 * Override WebSocket factory. If omitted, uses global WebSocket when available.
	 */
	wsFactory?: WsFactory
	wsPath?: string
}

export type TerminalSessionState
	= | 'idle'
		| 'connecting'
		| 'ready'
		| 'authed'
		| 'starting'
		| 'started'
		| 'closed'
		| 'error'

export type TerminalSessionConnectOptions = {
	/**
	 * kubeconfig used to authenticate the websocket session.
	 */
	kubeconfig: string
	/**
	 * Target pod/container for the Kubernetes exec session.
	 */
	target: ExecTarget
	/**
	 * Provide initial terminal size (cols/rows). If omitted, you can call `resize()` later.
	 * Note: server will only start exec after receiving the first resize.
	 */
	initialSize?: { cols: number, rows: number }
	/**
	 * If true, sends kubeconfig as the first auth frame instead of a subprotocol token.
	 * Default: false (offer kubeconfig in Sec-WebSocket-Protocol).
	 */
	authInMessage?: boolean
}

function defaultWsFactory(): WsFactory {
	const ws = (globalThis as unknown as { WebSocket?: unknown }).WebSocket
	if (typeof ws !== 'function')
		throw new Error('WebSocket is not available. Provide ProtocolClientOptions.wsFactory.')
	return (url: string, protocols?: string | string[]) => new (ws as new (url: string, protocols?: string | string[]) => WsLike)(url, protocols)
}

function joinUrl(base: string, path: string): string {
	const u = new URL(base)
	const p = path.startsWith('/') ? path : `/${path}`
	u.pathname = p
	return u.toString()
}

function toWsUrl(httpBase: string, wsPath: string, target: ExecTarget): string {
	const u = new URL(joinUrl(httpBase, wsPath))
	u.protocol = u.protocol === 'https:' ? 'wss:' : 'ws:'
	const namespace = target.namespace.trim()
	const pod = target.pod.trim()
	if (namespace.length === 0)
		throw new Error('target.namespace is required')
	if (pod.length === 0)
		throw new Error('target.pod is required')
	u.searchParams.set('namespace', namespace)
	u.searchParams.set('pod', pod)
	const container = typeof target.container === 'string' ? target.container.trim() : ''
	if (container.length > 0)
		u.searchParams.set('container', container)
	for (const commandPart of target.command ?? []) {
		const value = commandPart.trim()
		if (value.length > 0)
			u.searchParams.append('command', value)
	}
	return u.toString()
}

async function normalizeBinary(data: unknown): Promise<Uint8Array | null> {
	if (data instanceof Uint8Array)
		return data
	if (data instanceof ArrayBuffer)
		return new Uint8Array(data)

	// Blob (browser)
	const maybeBlob = data as { arrayBuffer?: () => Promise<ArrayBuffer> } | null
	if (maybeBlob && typeof maybeBlob.arrayBuffer === 'function') {
		const buf = await maybeBlob.arrayBuffer()
		return new Uint8Array(buf)
	}

	return null
}

async function createOpenPromise(ws: WsLike): Promise<void> {
	if (ws.readyState === 1)
		return
	return new Promise((resolve, reject) => {
		function cleanup(): void {
			try {
				ws.removeEventListener?.('open', onOpen)
			}
			catch {}
			try {
				ws.removeEventListener?.('error', onError as never)
			}
			catch {}
			if (ws.onopen === onOpen)
				ws.onopen = null
			if (ws.onerror === onError)
				ws.onerror = null
		}

		function onOpen(): void {
			cleanup()
			resolve()
		}

		function onError(ev: unknown): void {
			cleanup()
			reject(ev)
		}

		if (typeof ws.addEventListener === 'function') {
			ws.addEventListener('open', onOpen)
			ws.addEventListener('error', onError as never)
		}
		else {
			ws.onopen = onOpen
			ws.onerror = onError
		}
	})
}

export async function connectTerminalStreams(options: ConnectTerminalStreamsOptions): Promise<TerminalStreams> {
	const baseUrl = options.client.baseUrl.replace(/\/$/, '')
	const wsPath = options.client.wsPath ?? '/exec'
	const wsFactory = options.client.wsFactory ?? defaultWsFactory()
	const kubeconfig = options.connect.kubeconfig.trim()
	if (kubeconfig.length === 0)
		throw new Error('kubeconfig is required')

	const ac = new AbortController()
	if (options.signal) {
		if (options.signal.aborted) {
			ac.abort()
		}
		else {
			options.signal.addEventListener('abort', () => ac.abort(), { once: true })
		}
	}

	const wsUrl = toWsUrl(baseUrl, wsPath, options.connect.target)
	const protocols = options.connect.authInMessage === true
		? [TTY_WS_SUBPROTOCOL]
		: [
				TTY_WS_SUBPROTOCOL,
				encodeKubeconfigSubprotocol(kubeconfig),
			]
	let ws: WsLike
	try {
		ws = wsFactory(wsUrl, protocols)
	}
	catch (err) {
		throw new Error(`failed to create WebSocket: ${toErrorMessage(err)}`)
	}

	// Prefer deterministic binary in browsers.
	if (typeof ws.binaryType === 'string')
		ws.binaryType = 'arraybuffer'

	const openP = createOpenPromise(ws)

	let stateCtrl: Ctrl<TerminalSessionState> | null = null
	let framesCtrl: Ctrl<ServerFrame> | null = null
	let stdoutCtrl: Ctrl<Uint8Array> | null = null

	let state: TerminalSessionState = 'connecting'
	let pendingResize: { cols: number, rows: number } | null = options.connect.initialSize ?? null
	let initialResizeSent = false

	const stateStream = new ReadableStream<TerminalSessionState>({
		start(controller) {
			stateCtrl = controller
			controller.enqueue(state)
		},
		cancel() {
			stateCtrl = null
		},
	})

	const framesStream = new ReadableStream<ServerFrame>({
		start(controller) {
			framesCtrl = controller
		},
		cancel() {
			framesCtrl = null
		},
	})

	const stdoutStream = new ReadableStream<Uint8Array>({
		start(controller) {
			stdoutCtrl = controller
		},
		cancel() {
			stdoutCtrl = null
		},
	})

	const setState = (next: TerminalSessionState) => {
		if (state === next)
			return
		state = next
		if (stateCtrl)
			stateCtrl.enqueue(next)
	}

	const sendCtrl = async (frame: unknown) => {
		await openP
		ws.send(safeJsonStringify(frame))
	}

	const flushResizeIfPossible = async () => {
		if (!pendingResize)
			return
		if (initialResizeSent)
			return
		if (state !== 'authed' && state !== 'starting' && state !== 'started')
			return
		const { cols, rows } = pendingResize
		pendingResize = null
		initialResizeSent = true
		setState(state === 'authed' ? 'starting' : state)
		await sendCtrl({ type: 'resize', cols, rows })
	}

	const onMessage = async (ev: { data: unknown }) => {
		const u8 = await normalizeBinary(ev.data)
		if (u8) {
			if (stdoutCtrl)
				stdoutCtrl.enqueue(u8)
			return
		}

		if (typeof ev.data !== 'string')
			return

		let msg: unknown
		try {
			msg = JSON.parse(ev.data)
		}
		catch {
			return
		}

		const frame = msg as Partial<ServerFrame> | null
		if (!frame || typeof frame.type !== 'string')
			return

		if (framesCtrl)
			framesCtrl.enqueue(frame as ServerFrame)

		if (frame.type === 'ready')
			setState(state === 'authed' || state === 'starting' || state === 'started' ? state : 'ready')
		if (frame.type === 'authed') {
			setState('authed')
			void flushResizeIfPossible()
		}
		if (frame.type === 'started')
			setState('started')
		if (frame.type === 'error')
			setState('error')
	}

	const onClose = (_ev: WsCloseEvent) => {
		setState('closed')
		tryClose(stateCtrl)
		tryClose(framesCtrl)
		tryClose(stdoutCtrl)
	}

	const onError = (ev: unknown) => {
		const err = new Error(`WebSocket error: ${toErrorMessage(ev)}`)
		tryError(stateCtrl, err)
		tryError(framesCtrl, err)
		tryError(stdoutCtrl, err)
	}

	if (typeof ws.addEventListener === 'function') {
		ws.addEventListener('message', onMessage as never)
		ws.addEventListener('close', onClose as never)
		ws.addEventListener('error', onError as never)
	}
	else {
		ws.onmessage = onMessage as never
		ws.onclose = onClose
		ws.onerror = onError
	}

	// Auth after open when kubeconfig is not offered in subprotocols.
	if (options.connect.authInMessage === true) {
		void openP.then(async () => {
			await sendCtrl({ type: 'auth', kubeconfig })
		}).catch(() => {})
	}

	// When kubeconfig is offered in subprotocols, server may auth before the first resize.
	void openP.then(() => setState('connecting')).catch(() => {})

	const stdin = new WritableStream<Uint8Array>({
		async write(chunk) {
			await openP
			ws.send(chunk)
		},
		close() {
			try {
				ws.close()
			}
			catch {}
		},
		abort(reason) {
			try {
				ws.close(1000, typeof reason === 'string' ? reason : 'aborted')
			}
			catch {}
		},
	})

	const resize = (cols: number, rows: number) => {
		if (!Number.isInteger(cols) || cols < 1 || !Number.isInteger(rows) || rows < 1)
			return
		if (!initialResizeSent)
			pendingResize = { cols, rows }
		else
			void sendCtrl({ type: 'resize', cols, rows }).catch(() => {})

		void flushResizeIfPossible()
	}

	const close = (code?: number, reason?: string) => {
		try {
			ws.close(code, reason)
		}
		catch {}
	}

	if (ac.signal.aborted) {
		close(1000, 'aborted')
	}
	else {
		ac.signal.addEventListener('abort', () => close(1000, 'aborted'), { once: true })
	}

	return {
		state: stateStream,
		frames: framesStream,
		stdout: stdoutStream,
		stdin,
		resize,
		close,
	}
}
