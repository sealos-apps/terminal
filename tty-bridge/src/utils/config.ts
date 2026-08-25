import { readFile } from 'node:fs/promises'
import { z } from 'zod'

export type AppConfig = Readonly<{
	PORT: number
	KUBE_API_SERVER: string

	WS_MAX_PAYLOAD_BYTES: number
	WS_HEARTBEAT_INTERVAL_MS: number

	WS_AUTH_TIMEOUT_MS: number
	WS_MAX_KUBECONFIG_BYTES: number

	/**
	 * Requests with missing/unknown Origin are always rejected. Production
	 * deployments must provide the exact frontend Origin here.
	 */
	WS_ALLOWED_ORIGINS: string[]
}>

type Mutable<T> = { -readonly [K in keyof T]: T[K] }

const DEFAULT_CONFIG: AppConfig = Object.freeze({
	PORT: 3000,
	KUBE_API_SERVER: '',

	WS_MAX_PAYLOAD_BYTES: 1024 * 1024,
	WS_HEARTBEAT_INTERVAL_MS: 30_000,

	WS_AUTH_TIMEOUT_MS: 10_000,
	WS_MAX_KUBECONFIG_BYTES: 256 * 1024,

	WS_ALLOWED_ORIGINS: [],
})

function resolveKubeApiServer(value: string): string {
	if (value !== 'auto')
		return value

	const host = process.env['KUBERNETES_SERVICE_HOST']?.trim() ?? ''
	const port = process.env['KUBERNETES_SERVICE_PORT_HTTPS']?.trim() ?? ''
	if (host.length === 0 || port.length === 0)
		throw new Error('[config] KUBE_API_SERVER="auto" requires KUBERNETES_SERVICE_HOST and KUBERNETES_SERVICE_PORT_HTTPS.')

	const normalizedHost = host.includes(':') && !host.startsWith('[') ? `[${host}]` : host
	return `https://${normalizedHost}:${port}`
}

const ConfigFileSchema = z.object({
	PORT: z.number().int().min(1).max(65535).optional(),
	KUBE_API_SERVER: z.string().trim().min(1).optional(),

	WS_MAX_PAYLOAD_BYTES: z.number().int().min(1).optional(),
	WS_HEARTBEAT_INTERVAL_MS: z.number().int().min(1).optional(),

	WS_AUTH_TIMEOUT_MS: z.number().int().min(1).optional(),
	WS_MAX_KUBECONFIG_BYTES: z.number().int().min(1).optional(),

	WS_ALLOWED_ORIGINS: z.array(z.string().trim().min(1)).optional(),
}).strict()

/**
 * Centralized runtime config, loaded from `config.json` at startup.
 *
 * IMPORTANT:
 * - Keep config parsing/validation centralized here.
 * - Consumers should read `Config.xxx` directly (no extra fallback logic).
 */
export const Config: Mutable<AppConfig> = { ...DEFAULT_CONFIG }

export async function loadConfig(): Promise<void> {
	// `src/utils/config.ts` -> project root `config.json`
	const configUrl = new URL('../../config.json', import.meta.url)

	let raw: string
	try {
		raw = await readFile(configUrl, 'utf8')
	}
	catch (err: unknown) {
		throw new Error(`[config] Failed to read config.json at ${configUrl.pathname}: ${err instanceof Error ? err.message : String(err)}`)
	}

	let json: unknown
	try {
		json = JSON.parse(raw)
	}
	catch {
		throw new Error('[config] config.json is not valid JSON.')
	}

	const parsed = ConfigFileSchema.safeParse(json)
	if (!parsed.success) {
		const detail = parsed.error.issues
			.map(i => `${i.path.join('.') || '<root>'}: ${i.message}`)
			.join('; ')
		throw new Error(`[config] Invalid config.json: ${detail}`)
	}

	const v = parsed.data
	const next: AppConfig = {
		...DEFAULT_CONFIG,
		...v,
		KUBE_API_SERVER: typeof v.KUBE_API_SERVER === 'string' ? resolveKubeApiServer(v.KUBE_API_SERVER) : DEFAULT_CONFIG.KUBE_API_SERVER,
		WS_ALLOWED_ORIGINS: v.WS_ALLOWED_ORIGINS ?? DEFAULT_CONFIG.WS_ALLOWED_ORIGINS,
	}

	Object.assign(Config, next)
	Object.freeze(Config)
}
