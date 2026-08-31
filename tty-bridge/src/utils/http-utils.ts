import type { IncomingMessage, ServerResponse } from 'node:http'
import { Buffer } from 'node:buffer'
import { safeJsonStringify } from '@labring/sealos-tty-client'

export const HTTP_JSON_CONTENT_TYPE = 'application/json; charset=utf-8'

export const HTTP_ERRORS = {
	InvalidJsonBody: 'Invalid JSON body.',
	InvalidRequestBody: 'Invalid request body.',
	MissingKubeconfig: 'Missing required field: kubeconfig',
	MissingTargetFields: 'Missing required fields: namespace, pod',
	InvalidKubeconfig: 'Invalid kubeconfig.',
	UnsupportedKubeconfigCredentialPlugin: 'kubeconfig exec credential plugins are not supported for WebSocket authentication.',
	KubeconfigAuthenticationFailed: 'kubeconfig authentication failed.',
	KubeconfigValidationFailed: 'kubeconfig validation failed.',
	KubeconfigTooLarge: 'kubeconfig too large.',
	PayloadTooLarge: 'Payload too large.',
} as const

export type HttpErrorMessage = (typeof HTTP_ERRORS)[keyof typeof HTTP_ERRORS]

export function toStableKubeconfigError(message: string): HttpErrorMessage {
	const normalized = message.trim().toLowerCase()

	if (normalized === HTTP_ERRORS.KubeconfigTooLarge)
		return HTTP_ERRORS.KubeconfigTooLarge

	if (
		normalized.includes('exec credential plugin')
		|| normalized.includes('credential plugins are not supported')
	) {
		return HTTP_ERRORS.UnsupportedKubeconfigCredentialPlugin
	}

	if (
		normalized.includes('authentication failed')
		|| normalized.includes('unauthorized')
		|| normalized.includes('forbidden')
		|| normalized.includes('system:anonymous')
	) {
		return HTTP_ERRORS.KubeconfigAuthenticationFailed
	}

	if (
		normalized.includes('timed out')
		|| normalized.includes('validation failed')
	) {
		return HTTP_ERRORS.KubeconfigValidationFailed
	}

	return HTTP_ERRORS.InvalidKubeconfig
}

export type ExecTarget = {
	namespace: string
	pod: string
	container?: string
	/**
	 * Optional exec command override (argv array).
	 * When omitted, server will try common shells (bash/sh/ash).
	 */
	command?: string[]
}

export function parseUrl(req: IncomingMessage): URL {
	const host = req.headers.host ?? 'localhost'
	const raw = req.url ?? '/'
	return new URL(raw, `http://${host}`)
}

export function isOriginAllowed(allow: readonly string[], origin: string | undefined): boolean {
	if (allow.length === 0)
		return false
	if (typeof origin !== 'string' || origin.length === 0)
		return false
	return allow.includes(origin)
}

export function sendJson(res: ServerResponse, statusCode: number, payload: unknown): void {
	res.statusCode = statusCode
	res.setHeader('content-type', HTTP_JSON_CONTENT_TYPE)
	res.end(safeJsonStringify(payload))
}

export function sendJsonError(res: ServerResponse, statusCode: number, error: string): void {
	sendJson(res, statusCode, { ok: false, error })
}

export async function readBody(req: IncomingMessage, limitBytes: number): Promise<Buffer> {
	return new Promise((resolve, reject) => {
		const chunks: Buffer[] = []
		let total = 0
		req.on('data', (chunk: Buffer) => {
			total += chunk.length
			if (total > limitBytes) {
				reject(new Error(HTTP_ERRORS.PayloadTooLarge))
				req.destroy()
				return
			}
			chunks.push(chunk)
		})
		req.on('end', () => resolve(Buffer.concat(chunks)))
		req.on('error', reject)
	})
}

export function parseExecQuery(req: IncomingMessage): { ok: true, target: ExecTarget } | { ok: false, error: string } {
	const url = parseUrl(req)
	const namespace = url.searchParams.get('namespace')?.trim() ?? ''
	const pod = url.searchParams.get('pod')?.trim() ?? ''
	if (namespace.length === 0 || pod.length === 0)
		return { ok: false, error: HTTP_ERRORS.MissingTargetFields }

	const containerValue = url.searchParams.get('container')?.trim() ?? ''
	const command = url.searchParams
		.getAll('command')
		.map(value => value.trim())
		.filter(value => value.length > 0)

	return {
		ok: true,
		target: {
			namespace,
			pod,
			container: containerValue.length > 0 ? containerValue : undefined,
			command: command.length > 0 ? command : undefined,
		},
	}
}
