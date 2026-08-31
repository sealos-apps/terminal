import type { Server as HttpServer, IncomingMessage } from 'node:http'
import type { Socket } from 'node:net'
import type { RawData } from 'ws'
import type WebSocket from 'ws'
import type { ClientFrame } from '../packages/protocol-client/src/protocol.ts'
import type { Session, WsConnection } from './terminal-session.ts'
import type { KubeconfigResult } from './utils/k8s/kubeconfig.ts'

import { Buffer } from 'node:buffer'
import { randomUUID } from 'node:crypto'
import { WebSocketServer } from 'ws'
import {
	decodeKubeconfigSubprotocol,
	safeParseClientFrame,
	toErrorMessage,
	TTY_WS_SUBPROTOCOL,
} from '../packages/protocol-client/src/protocol.ts'

import { cleanupSession, sendCtrl, startExecIfNeeded } from './terminal-session.ts'
import { withTimeout } from './utils/async.ts'
import { Config } from './utils/config.ts'
import { HTTP_ERRORS, isOriginAllowed, parseExecQuery, parseUrl, toStableKubeconfigError } from './utils/http-utils.ts'
import { validateAndSanitizeKubeConfig } from './utils/k8s/kubeconfig.ts'
import { logInfo, logWarn } from './utils/logger.ts'
import { markAliveOnPong, startHeartbeat } from './utils/ws-heartbeat.ts'
import { rawToBuffer, rawToString } from './utils/ws-message.ts'
import { createWsStreams } from './utils/ws-streams.ts'

type WsSendable = string | Uint8Array

function getOfferedKubeconfig(req: IncomingMessage): string | undefined {
	const raw = req.headers['sec-websocket-protocol']
	const header = Array.isArray(raw) ? raw.join(',') : raw
	if (typeof header !== 'string' || header.length === 0)
		return undefined

	for (const protocol of header.split(',').map(token => token.trim()).filter(token => token.length > 0)) {
		const kubeconfig = decodeKubeconfigSubprotocol(protocol)
		if (typeof kubeconfig === 'string')
			return kubeconfig
	}

	return undefined
}

async function authenticateSession(
	conn: WsConnection,
	sess: Session,
	kubeconfigRaw: string,
	source: 'subprotocol' | 'message',
	isSessionAlive: () => boolean,
	onAuthStarted: () => void,
	onAuthFailed: (message: string) => void,
): Promise<void> {
	if (typeof sess.kubeconfig === 'string' && sess.kubeconfig.length > 0) {
		sendCtrl(conn, { type: 'authed' })
		return
	}
	if (sess.authenticating)
		return
	if (Buffer.byteLength(kubeconfigRaw, 'utf8') > Config.WS_MAX_KUBECONFIG_BYTES) {
		const message = HTTP_ERRORS.KubeconfigTooLarge
		logWarn(`ws auth failed (${source})`, { id: conn.id, error: message })
		onAuthFailed(message)
		return
	}

	sess.authStarted = true
	sess.authenticating = true
	onAuthStarted()
	const result = await withTimeout<KubeconfigResult<string>>(
		validateAndSanitizeKubeConfig(kubeconfigRaw),
		Config.WS_AUTH_TIMEOUT_MS,
		() => ({ ok: false, message: 'Authentication timed out while validating kubeconfig.' }),
	)
	sess.authenticating = false
	if (!isSessionAlive())
		return

	if (result.ok) {
		sess.kubeconfig = result.value
		sendCtrl(conn, { type: 'authed' })
		logInfo(`ws authed (${source})`, { id: conn.id })
		return
	}

	logWarn(`ws auth failed (${source})`, { id: conn.id, error: result.message })
	onAuthFailed(toStableKubeconfigError(result.message))
}
function makeConnection(ws: WebSocket): WsConnection {
	const id = randomUUID()
	return {
		id,
		send: (data: WsSendable) => ws.send(data),
		close: (code?: number, reason?: string) => ws.close(code, reason),
	}
}

export function attachTerminalWebSocketServer(server: HttpServer): WebSocketServer {
	const wss = new WebSocketServer({
		noServer: true,
		handleProtocols: protocols => protocols.has(TTY_WS_SUBPROTOCOL) ? TTY_WS_SUBPROTOCOL : false,
		maxPayload: Config.WS_MAX_PAYLOAD_BYTES,
		perMessageDeflate: false,
	})

	startHeartbeat(wss, Config.WS_HEARTBEAT_INTERVAL_MS)

	const sessions = new Map<string, Session>()

	server.on('upgrade', (req: IncomingMessage, socket: Socket, head: Buffer) => {
		const url = parseUrl(req)
		if (url.pathname !== '/exec') {
			socket.destroy()
			return
		}

		if (!isOriginAllowed(Config.WS_ALLOWED_ORIGINS, typeof req.headers.origin === 'string' ? req.headers.origin : undefined)) {
			socket.destroy()
			return
		}

		wss.handleUpgrade(req, socket, head, (ws) => {
			wss.emit('connection', ws, req)
		})
	})

	wss.on('connection', (ws, req) => {
		markAliveOnPong(ws)

		const parsed = parseExecQuery(req)
		if (!parsed.ok) {
			ws.close(1008, parsed.error)
			return
		}

		const conn = makeConnection(ws)
		logInfo('ws connected', { id: conn.id })

		const streams = createWsStreams(ws)
		const sess: Session = {
			authStarted: false,
			authenticating: false,
			started: false,
			starting: false,
			target: parsed.target,
			streams,
		}
		sessions.set(conn.id, sess)

		let authTimeout: ReturnType<typeof setTimeout> | undefined = setTimeout(() => {
			const current = sessions.get(conn.id)
			if (!current)
				return
			if (current.authStarted || (typeof current.kubeconfig === 'string' && current.kubeconfig.length > 0))
				return
			sendCtrl(conn, { type: 'error', message: 'Auth timeout: offer kubeconfig in Sec-WebSocket-Protocol or send { "type": "auth", "kubeconfig": "..." } as the first WebSocket message.' })
			logWarn('ws auth timeout', { id: conn.id })
			sessions.delete(conn.id)
			cleanupSession(current)
			try {
				conn.close(1008, 'auth timeout')
			}
			catch {}
		}, Config.WS_AUTH_TIMEOUT_MS)

		const cancelAuthTimeout = () => {
			if (!authTimeout)
				return
			clearTimeout(authTimeout)
			authTimeout = undefined
		}

		const closeSession = (session: Session, code: number, reason: string) => {
			cancelAuthTimeout()
			sessions.delete(conn.id)
			cleanupSession(session)
			try {
				conn.close(code, reason)
			}
			catch {}
		}

		const failAuthentication = (message: string) => {
			sendCtrl(conn, { type: 'error', message })
			closeSession(sess, 1008, 'invalid kubeconfig')
		}

		sendCtrl(conn, { type: 'ready' })

		const offeredKubeconfig = getOfferedKubeconfig(req)
		if (typeof offeredKubeconfig === 'string' && offeredKubeconfig.length > 0) {
			void authenticateSession(
				conn,
				sess,
				offeredKubeconfig,
				'subprotocol',
				() => sessions.get(conn.id) === sess,
				cancelAuthTimeout,
				failAuthentication,
			)
		}

		const handleCtrl = async (frame: ClientFrame): Promise<void> => {
			const current = sessions.get(conn.id)
			if (!current)
				return

			if (frame.type === 'auth') {
				await authenticateSession(
					conn,
					current,
					frame.kubeconfig,
					'message',
					() => sessions.get(conn.id) === current,
					cancelAuthTimeout,
					failAuthentication,
				)
				return
			}

			if (frame.type === 'ping') {
				sendCtrl(conn, { type: 'pong' })
				return
			}

			if (typeof current.kubeconfig !== 'string' || current.kubeconfig.length === 0) {
				sendCtrl(conn, { type: 'error', message: 'Not authenticated. Offer kubeconfig in Sec-WebSocket-Protocol or send { "type": "auth", "kubeconfig": "..." } first.' })
				logWarn('ws rejected: not authenticated', { id: conn.id })
				closeSession(current, 1008, 'not authenticated')
				return
			}

			if (frame.type === 'resize') {
				if (!current.started) {
					await startExecIfNeeded(conn, current, { cols: frame.cols, rows: frame.rows })
					return
				}
				current.stdout?.resize(frame.cols, frame.rows)
				return
			}

			if (frame.type === 'stdin') {
				try {
					current.streams.stdin.write(frame.data)
				}
				catch (err: unknown) {
					sendCtrl(conn, { type: 'error', message: toErrorMessage(err) })
				}
			}
		}

		const handleMessage = async (data: RawData, isBinary: boolean): Promise<void> => {
			const sess = sessions.get(conn.id)
			if (!sess)
				return

			if (isBinary) {
				if (typeof sess.kubeconfig !== 'string' || sess.kubeconfig.length === 0) {
					sendCtrl(conn, { type: 'error', message: 'Not authenticated. Offer kubeconfig in Sec-WebSocket-Protocol or send { "type": "auth", "kubeconfig": "..." } first.' })
					logWarn('ws rejected (binary): not authenticated', { id: conn.id })
					closeSession(sess, 1008, 'not authenticated')
					return
				}
				const buf = rawToBuffer(data)
				try {
					sess.streams.stdin.write(buf)
				}
				catch (err: unknown) {
					sendCtrl(conn, { type: 'error', message: toErrorMessage(err) })
				}
				return
			}

			let value: unknown
			try {
				value = JSON.parse(rawToString(data))
			}
			catch {
				sendCtrl(conn, { type: 'error', message: 'Invalid JSON message.' })
				return
			}

			const parsedFrame = safeParseClientFrame(value)
			if (!parsedFrame.ok) {
				logWarn('ws invalid client frame', { id: conn.id, error: parsedFrame.error })
				sendCtrl(conn, { type: 'error', message: 'Invalid client frame.' })
				return
			}

			// Control frames go through ctrl stream for a unified flow.
			sess.streams.ctrl.write(parsedFrame.frame)
		}

		ws.on('message', (data: RawData, isBinary: boolean) => {
			void handleMessage(data, isBinary)
		})

		// ctrl-consumer: drive init/ping/resize/stdin from stream
		streams.ctrl.on('data', (frame: unknown) => {
			const parsedFrame = safeParseClientFrame(frame)
			if (!parsedFrame.ok) {
				logWarn('ws invalid client frame (ctrl stream)', { id: conn.id, error: parsedFrame.error })
				sendCtrl(conn, { type: 'error', message: 'Invalid client frame.' })
				return
			}
			void handleCtrl(parsedFrame.frame)
		})

		ws.on('close', () => {
			cancelAuthTimeout()
			const sess = sessions.get(conn.id)
			sessions.delete(conn.id)
			if (!sess)
				return

			logInfo('ws closed', { id: conn.id })
			cleanupSession(sess)
		})

		ws.on('error', (err) => {
			logWarn('ws error', { id: conn.id, error: toErrorMessage(err) })
		})
	})

	return wss
}
