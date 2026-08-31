import * as k8s from '@kubernetes/client-node'
import { Config } from '../config.ts'

type RawNamedCluster = {
	name?: string
	cluster?: Record<string, unknown>
}

type RawNamedContext = {
	name?: string
	context?: {
		cluster?: string
		user?: string
		[key: string]: unknown
	}
}

type RawNamedUser = {
	name?: string
	user?: Record<string, unknown>
}

type RawKubeConfig = {
	apiVersion?: string
	kind?: string
	preferences?: Record<string, unknown>
	clusters?: RawNamedCluster[]
	contexts?: RawNamedContext[]
	users?: RawNamedUser[]
	['current-context']?: string
	[key: string]: unknown
}

export type KubeconfigResult<T> = { ok: true, value: T } | { ok: false, message: string }

function fail<T>(message: string): KubeconfigResult<T> {
	return { ok: false, message }
}

function ok<T>(value: T): KubeconfigResult<T> {
	return { ok: true, value }
}

export function loadKubeConfigFromString(kubeconfig: string): KubeconfigResult<k8s.KubeConfig> {
	const kc = new k8s.KubeConfig()

	try {
		kc.loadFromString(kubeconfig)
	}
	catch (error: unknown) {
		return fail(error instanceof Error ? error.message : 'Invalid kubeconfig.')
	}

	if (Config.KUBE_API_SERVER) {
		const currentCluster = kc.getCurrentCluster()
		if (currentCluster) {
			kc.clusters = kc.clusters.map(cluster => cluster.name === currentCluster.name
				? { ...cluster, server: Config.KUBE_API_SERVER }
				: cluster)
		}
	}

	return ok(kc)
}

async function parseRawKubeConfig(kubeconfig: string): Promise<KubeconfigResult<RawKubeConfig>> {
	try {
		return ok(JSON.parse(kubeconfig) as RawKubeConfig)
	}
	catch {
		try {
			const parsed = k8s.loadYaml<RawKubeConfig>(kubeconfig)
			if (parsed == null || typeof parsed !== 'object' || Array.isArray(parsed))
				return fail('kubeconfig root must be an object.')
			return ok(parsed)
		}
		catch (error: unknown) {
			return fail(error instanceof Error ? error.message : 'Invalid kubeconfig.')
		}
	}
}

function getRequiredCurrentContext(kc: k8s.KubeConfig): KubeconfigResult<k8s.Context> {
	const currentContextName = kc.getCurrentContext()
	const currentContext = currentContextName ? kc.getContextObject(currentContextName) : null
	if (!currentContext)
		return fail('kubeconfig missing current context.')
	return ok(currentContext)
}

function getRequiredCurrentCluster(kc: k8s.KubeConfig): KubeconfigResult<k8s.Cluster> {
	const currentCluster = kc.getCurrentCluster()
	if (!currentCluster)
		return fail('kubeconfig missing current cluster.')
	return ok(currentCluster)
}

function hasExecCredentialPlugin(kc: k8s.KubeConfig): boolean {
	return kc.users.some(user => user.exec != null)
}

async function assertAuthenticated(kc: k8s.KubeConfig): Promise<KubeconfigResult<undefined>> {
	try {
		const authApi = kc.makeApiClient(k8s.AuthenticationV1Api)
		const review = await authApi.createSelfSubjectReview({
			body: {
				apiVersion: 'authentication.k8s.io/v1',
				kind: 'SelfSubjectReview',
			},
		})

		const username = review.status?.userInfo?.username?.trim()
		if (username == null || username.length === 0 || username === 'system:anonymous')
			return fail('kubeconfig authentication failed.')

		return ok(undefined)
	}
	catch (error: unknown) {
		if (error instanceof k8s.ApiException) {
			if (error.code === 401 || error.code === 403)
				return fail(error.message)
			return fail(error.message)
		}

		if (error instanceof Error)
			return fail(error.message)

		return fail('kubeconfig validation failed.')
	}
}

export async function sanitizeKubeConfig(kubeconfig: string): Promise<KubeconfigResult<string>> {
	const rawResult = await parseRawKubeConfig(kubeconfig)
	if (!rawResult.ok)
		return rawResult

	const kcResult = loadKubeConfigFromString(kubeconfig)
	if (!kcResult.ok)
		return kcResult

	const currentContextResult = getRequiredCurrentContext(kcResult.value)
	if (!currentContextResult.ok)
		return currentContextResult

	const currentClusterResult = getRequiredCurrentCluster(kcResult.value)
	if (!currentClusterResult.ok)
		return currentClusterResult

	const currentUser = kcResult.value.getCurrentUser()
	const matchingContext = rawResult.value.contexts?.find(context => context.name === currentContextResult.value.name)
	if (!matchingContext?.context)
		return fail('kubeconfig missing current context entry.')

	const matchingCluster = rawResult.value.clusters?.find(cluster => cluster.name === currentClusterResult.value.name)
	if (!matchingCluster?.cluster)
		return fail('kubeconfig missing current cluster entry.')

	const userName = currentUser?.name ?? matchingContext.context.user
	const matchingUser = userName == null
		? undefined
		: rawResult.value.users?.find(user => user.name === userName)

	const sanitizedCluster: RawNamedCluster = {
		...matchingCluster,
		cluster: {
			...matchingCluster.cluster,
			...(Config.KUBE_API_SERVER ? { server: Config.KUBE_API_SERVER } : {}),
		},
	}

	return ok(JSON.stringify({
		'apiVersion': typeof rawResult.value.apiVersion === 'string' ? rawResult.value.apiVersion : 'v1',
		'kind': typeof rawResult.value.kind === 'string' ? rawResult.value.kind : 'Config',
		'clusters': [sanitizedCluster],
		'contexts': [matchingContext],
		'users': matchingUser ? [matchingUser] : [],
		'current-context': currentContextResult.value.name,
	} satisfies RawKubeConfig))
}

export async function validateAndSanitizeKubeConfig(kubeconfig: string): Promise<KubeconfigResult<string>> {
	const kcResult = loadKubeConfigFromString(kubeconfig)
	if (!kcResult.ok)
		return kcResult

	const currentContextResult = getRequiredCurrentContext(kcResult.value)
	if (!currentContextResult.ok)
		return currentContextResult

	const currentClusterResult = getRequiredCurrentCluster(kcResult.value)
	if (!currentClusterResult.ok)
		return currentClusterResult

	if (hasExecCredentialPlugin(kcResult.value))
		return fail('kubeconfig exec credential plugins are not supported for WebSocket authentication.')

	const authResult = await assertAuthenticated(kcResult.value)
	if (!authResult.ok)
		return authResult

	return sanitizeKubeConfig(kubeconfig)
}
