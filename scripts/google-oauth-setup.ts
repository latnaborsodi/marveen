// One-shot OAuth flow to mint a refresh_token for the heartbeat's Google
// Calendar reads. Run with `tsx scripts/google-oauth-setup.ts`. The script
// prints an auth URL; open it in a browser, approve, and the local callback
// captures the code, exchanges it for tokens, and writes them to disk.

import http from 'node:http'
import https from 'node:https'
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { homedir } from 'node:os'
import { join, dirname } from 'node:path'

const CLIENT_CREDS_PATH = join(homedir(), '.gmail-mcp', 'gcp-oauth.keys.json')
const TOKENS_PATH = join(homedir(), '.config', 'google-calendar-mcp', 'tokens.json')
const PORT = 8765
const REDIRECT_URI = `http://localhost:${PORT}/callback`
const SCOPE = 'https://www.googleapis.com/auth/calendar.readonly'

interface ClientCredentials {
  installed: { client_id: string; client_secret: string; token_uri: string }
}

function loadClient(): ClientCredentials {
  return JSON.parse(readFileSync(CLIENT_CREDS_PATH, 'utf-8'))
}

function buildAuthUrl(client: ClientCredentials): string {
  const params = new URLSearchParams({
    client_id: client.installed.client_id,
    redirect_uri: REDIRECT_URI,
    response_type: 'code',
    scope: SCOPE,
    access_type: 'offline',
    prompt: 'consent',
  })
  return `https://accounts.google.com/o/oauth2/v2/auth?${params}`
}

function postForm(url: string, body: URLSearchParams): Promise<{ status: number; data: string }> {
  return new Promise((resolve, reject) => {
    const req = https.request(
      url,
      { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' } },
      (res) => {
        const chunks: Buffer[] = []
        res.on('data', (c: Buffer) => chunks.push(c))
        res.on('end', () => resolve({ status: res.statusCode ?? 0, data: Buffer.concat(chunks).toString('utf-8') }))
        res.on('error', reject)
      }
    )
    req.on('error', reject)
    req.write(body.toString())
    req.end()
  })
}

async function exchangeCode(client: ClientCredentials, code: string) {
  const body = new URLSearchParams({
    code,
    client_id: client.installed.client_id,
    client_secret: client.installed.client_secret,
    redirect_uri: REDIRECT_URI,
    grant_type: 'authorization_code',
  })
  const { status, data } = await postForm('https://oauth2.googleapis.com/token', body)
  if (status !== 200) throw new Error(`Token exchange failed (${status}): ${data}`)
  return JSON.parse(data) as {
    access_token: string
    refresh_token: string
    expires_in: number
    scope: string
    token_type: string
  }
}

function saveTokens(t: { access_token: string; refresh_token: string; expires_in: number; scope: string; token_type: string }) {
  const tokens = {
    normal: {
      access_token: t.access_token,
      refresh_token: t.refresh_token,
      expiry_date: Date.now() + t.expires_in * 1000,
      token_type: t.token_type,
      scope: t.scope,
    },
  }
  mkdirSync(dirname(TOKENS_PATH), { recursive: true })
  writeFileSync(TOKENS_PATH, JSON.stringify(tokens, null, 2), { mode: 0o600 })
}

async function main() {
  const client = loadClient()
  const authUrl = buildAuthUrl(client)

  console.log('\n=== GOOGLE OAUTH FLOW ===')
  console.log('Open this URL in a browser on a machine that can reach localhost:%d:', PORT)
  console.log()
  console.log(authUrl)
  console.log()
  console.log('Waiting for callback on %s ...', REDIRECT_URI)

  const code: string = await new Promise((resolve, reject) => {
    const server = http.createServer((req, res) => {
      if (!req.url) return
      const url = new URL(req.url, `http://localhost:${PORT}`)
      if (url.pathname !== '/callback') {
        res.writeHead(404)
        res.end('not found')
        return
      }
      const got = url.searchParams.get('code')
      const err = url.searchParams.get('error')
      if (err) {
        res.writeHead(400, { 'Content-Type': 'text/plain' })
        res.end(`OAuth error: ${err}`)
        server.close()
        reject(new Error(err))
        return
      }
      if (!got) {
        res.writeHead(400, { 'Content-Type': 'text/plain' })
        res.end('Missing code')
        server.close()
        reject(new Error('Missing code in callback'))
        return
      }
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' })
      res.end('OK — visszamehetsz a terminálba.')
      server.close()
      resolve(got)
    })
    server.listen(PORT, '127.0.0.1', () => {})
    server.on('error', reject)
  })

  console.log('Got authorization code, exchanging for tokens...')
  const tokens = await exchangeCode(client, code)
  if (!tokens.refresh_token) {
    throw new Error('No refresh_token in response — re-run with prompt=consent or revoke prior consent at https://myaccount.google.com/permissions')
  }
  saveTokens(tokens)
  console.log('Saved tokens to %s', TOKENS_PATH)
  console.log('Scope: %s', tokens.scope)
}

main().catch((err) => {
  console.error('OAuth setup failed:', err.message)
  process.exit(1)
})
