export async function withTimeout<T>(promise: Promise<T>, timeoutMs: number, onTimeout: () => T): Promise<T> {
	let timer: ReturnType<typeof setTimeout> | undefined

	try {
		return await Promise.race([
			promise,
			new Promise<T>((resolve) => {
				timer = setTimeout(() => resolve(onTimeout()), timeoutMs)
			}),
		])
	}
	finally {
		if (timer)
			clearTimeout(timer)
	}
}
