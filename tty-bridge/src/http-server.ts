import { createServer } from 'node:http'

import { parseUrl, sendJson } from './utils/http-utils.ts'

export function createHttpServer() {
	return createServer((req, res) => {
		// CORS (keep it simple for API usage from browsers)
		res.setHeader('access-control-allow-origin', '*')
		res.setHeader('access-control-allow-methods', 'GET,POST,OPTIONS')
		res.setHeader('access-control-allow-headers', 'content-type,sec-websocket-protocol')
		res.setHeader('access-control-max-age', '600')

		const url = parseUrl(req)
		if (req.method === 'OPTIONS') {
			res.statusCode = 204
			res.end()
			return
		}

		if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/healthz')) {
			sendJson(res, 200, { name: 'sealos-tty-bridge', ok: true })
			return
		}

		res.statusCode = 404
		res.setHeader('content-type', 'text/plain; charset=utf-8')
		res.end('Not Found')
	})
}
