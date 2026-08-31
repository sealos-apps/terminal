import type { V1Status } from '@kubernetes/client-node'
import assert from 'node:assert/strict'
import { PassThrough } from 'node:stream'
import { execFirstWorkingCommand } from './terminal-session.ts'

async function testExecFallbackProbesUntilWorkingShell(): Promise<void> {
	const calls: string[][] = []
	const closed: string[] = []
	const statuses: V1Status[] = []

	const fakeExec = {
		async exec(...args: unknown[]) {
			const command = args[3] as string[]
			const statusCallback = args[8] as (status: V1Status) => void
			calls.push(command)

			const ws = { close: () => closed.push(command.join(' ')) }
			if (command[0] === '/bin/bash' && command[1] === '-c') {
				queueMicrotask(() => statusCallback({
					status: 'Failure',
					message: 'exec: "/bin/bash": executable file not found',
				} as V1Status))
			}
			else if (command[0] === '/bin/sh' && command[1] === '-c') {
				queueMicrotask(() => statusCallback({ status: 'Success' } as V1Status))
			}

			return ws
		},
	}

	const ws = await execFirstWorkingCommand({
		exec: fakeExec,
		target: { namespace: 'default', pod: 'pod-1' },
		candidates: [['/bin/bash', '-il'], ['/bin/sh', '-i']],
		stdout: new PassThrough(),
		stdin: new PassThrough(),
		statusCallback: status => statuses.push(status),
	})

	assert.deepEqual(calls, [['/bin/bash', '-c', 'exit 0'], ['/bin/sh', '-c', 'exit 0'], ['/bin/sh', '-i']])
	assert.deepEqual(closed, [])
	assert.deepEqual(statuses, [])
	assert.ok(ws)
}

await testExecFallbackProbesUntilWorkingShell()
