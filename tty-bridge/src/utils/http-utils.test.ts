import assert from 'node:assert/strict'
import { isOriginAllowed } from './http-utils.ts'

function testExactOriginAllowlist(): void {
	const allowlist = ['https://terminal.example.com']

	assert.equal(isOriginAllowed(allowlist, 'https://terminal.example.com'), true)
	assert.equal(isOriginAllowed(allowlist, 'https://other.example.com'), false)
	assert.equal(isOriginAllowed(allowlist, 'https://terminal.example.com/'), false)
	assert.equal(isOriginAllowed(allowlist, undefined), false)
}

function testEmptyOriginAllowlistFailsClosed(): void {
	assert.equal(isOriginAllowed([], 'https://terminal.example.com'), false)
}

testExactOriginAllowlist()
testEmptyOriginAllowlistFailsClosed()
