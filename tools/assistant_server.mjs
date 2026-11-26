import { createServer } from 'node:http';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';

const secret = () => randomBytes(32).toString('base64url');
const hash = value => createHash('sha256').update(value).digest('base64url');
const now = () => Date.now();
const minute = 60_000;
const limits = { body: 4_000_000, scores: 20_000, setlists: 5_000 };
const scopes = ['library:read', 'setlists:write'];
const legacyVersions = ['2025-11-25', '2025-06-18', '2025-03-26'];
const modernVersion = '2026-07-28';
const idPattern = /^[a-zA-Z0-9:_-]{1,160}$/;
const tokenPattern = /^[a-zA-Z0-9_-]{43}$/;
const text = (value, max = 200) =>
  typeof value === 'string' && value.length <= max;
const validId = value => typeof value === 'string' && idPattern.test(value);
const esc = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;')
  .replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;');

const toolDefinitions = [
  {
    name: 'search_scores', description: 'Search EncoreSheets score metadata. Returns stable IDs for setlists.',
    inputSchema: { type: 'object', properties: { query: { type: 'string', maxLength: 200 } }, required: ['query'], additionalProperties: false },
    annotations: { readOnlyHint: true },
  },
  {
    name: 'list_setlists', description: 'List the latest setlists synced from EncoreSheets.',
    inputSchema: { type: 'object', properties: { offset: { type: 'integer', minimum: 0 } }, additionalProperties: false },
    annotations: { readOnlyHint: true },
  },
  {
    name: 'create_setlist', description: 'Propose a setlist in score ID order. Show the returned approval URL to the user. The request only queues after browser approval. Use the same request ID to retry.',
    inputSchema: { type: 'object', properties: {
      name: { type: 'string', minLength: 1, maxLength: 200 },
      score_ids: { type: 'array', minItems: 1, maxItems: 200, items: { type: 'string' } },
      request_id: { type: 'string', minLength: 1, maxLength: 160 },
    }, required: ['name', 'score_ids', 'request_id'], additionalProperties: false },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
  {
    name: 'get_setlist_request', description: 'Check whether your setlist request is awaiting approval, queued, saved, rejected, or canceled.',
    inputSchema: { type: 'object', properties: { request_id: { type: 'string', minLength: 1, maxLength: 160 } }, required: ['request_id'], additionalProperties: false },
    annotations: { readOnlyHint: true },
  },
];

class RequestError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function reply(res, status, value, headers = {}) {
  res.writeHead(status, { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
    ...(value == null ? {} : { 'Content-Type': 'application/json' }), ...headers });
  res.end(value == null ? undefined : JSON.stringify(value));
}

function page(res, status, title, body, callbackOrigin) {
  res.writeHead(status, {
    'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store',
    'Content-Security-Policy': "default-src 'none'; form-action 'self'" +
      (callbackOrigin ? ' ' + callbackOrigin : '') + "; frame-ancestors 'none'; base-uri 'none'",
    'Referrer-Policy': 'same-origin', 'X-Content-Type-Options': 'nosniff',
  });
  res.end('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>' +
    esc(title) + '</title><main><h1>' + esc(title) + '</h1>' + body + '</main></html>');
}

async function read(req, form = false) {
  const expected = form ? 'application/x-www-form-urlencoded' : 'application/json';
  if (req.headers['content-type']?.split(';')[0].trim() !== expected) {
    throw new RequestError(415, 'Unsupported content type');
  }
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > limits.body) throw new RequestError(413, 'Request too large');
    chunks.push(chunk);
  }
  const body = Buffer.concat(chunks).toString('utf8');
  if (form) return Object.fromEntries(new URLSearchParams(body));
  try {
    const value = JSON.parse(body);
    if (value && typeof value === 'object' && !Array.isArray(value)) return value;
  } catch {}
  throw new RequestError(400, 'Expected a JSON object');
}

function safeRedirect(value) {
  try {
    const url = new URL(value);
    return value.length <= 2048 && !url.hash && !url.username && !url.password &&
      (url.protocol === 'https:' || (url.protocol === 'http:' && ['127.0.0.1', '[::1]', 'localhost'].includes(url.hostname)));
  } catch { return false; }
}

function catalog(body) {
  const { scores, setlists } = body;
  if (!Array.isArray(scores) || !Array.isArray(setlists) ||
      scores.length > limits.scores || setlists.length > limits.setlists ||
      !scores.every(s => s && validId(s.id) && text(s.title) && text(s.composer) && text(s.duration, 40)) ||
      !setlists.every(s => s && validId(s.id) && text(s.name) && Array.isArray(s.score_ids) &&
        s.score_ids.length <= 1000 && s.score_ids.every(validId))) {
    throw new RequestError(400, 'Invalid catalog');
  }
  return {
    scores: scores.map(({ id, title, composer, duration }) => ({ id, title, composer, duration })),
    setlists: setlists.map(({ id, name, score_ids }) => ({ id, name, score_ids })),
  };
}

export function assistantServer({ origin, database, enrollmentKey }) {
  const base = new URL(origin);
  if (base.origin !== origin || !safeRedirect(origin) || !tokenPattern.test(enrollmentKey)) {
    throw new Error('Set an HTTPS origin (or loopback HTTP for development) and a 43-character base64url enrollment key.');
  }
  const resource = origin + '/mcp';
  const db = new DatabaseSync(database);
  db.exec(`
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS libraries (id TEXT PRIMARY KEY, token TEXT UNIQUE, catalog TEXT, synced INTEGER);
    CREATE TABLE IF NOT EXISTS pairing (code TEXT PRIMARY KEY, library TEXT, expires INTEGER);
    CREATE TABLE IF NOT EXISTS clients (id TEXT PRIMARY KEY, name TEXT, redirects TEXT);
    CREATE TABLE IF NOT EXISTS consent (id TEXT PRIMARY KEY, request TEXT, expires INTEGER);
    CREATE TABLE IF NOT EXISTS codes (id TEXT PRIMARY KEY, grant TEXT, request TEXT, expires INTEGER);
    CREATE TABLE IF NOT EXISTS grants (id TEXT PRIMARY KEY, library TEXT, client TEXT, scope TEXT, browser TEXT UNIQUE);
    CREATE TABLE IF NOT EXISTS tokens (id TEXT PRIMARY KEY, grant_id TEXT, kind TEXT, expires INTEGER);
    CREATE TABLE IF NOT EXISTS requests (id TEXT PRIMARY KEY, grant_id TEXT, client_key TEXT, name TEXT, scores TEXT, status TEXT, created INTEGER, UNIQUE(grant_id, client_key));
  `);
  const get = (sql, ...params) => db.prepare(sql).get(...params);
  const all = (sql, ...params) => db.prepare(sql).all(...params);
  const run = (sql, ...params) => db.prepare(sql).run(...params);
  const grantFor = (value, kind) => value && get(
    'SELECT grants.* FROM tokens JOIN grants ON grants.id = tokens.grant_id WHERE tokens.id = ? AND kind = ? AND expires > ?',
    hash(value), kind, now(),
  );
  const writeScope = grant => grant.scope.split(' ').includes(scopes[1]);
  const browserGrant = (req, id) => {
    const cookie = req.headers.cookie?.split(/;\s*/).find(value => value.startsWith('es_' + id + '='))?.split('=')[1];
    return cookie && get('SELECT * FROM grants WHERE id = ? AND browser = ?', id, hash(cookie));
  };
  const requestStatus = row => ({
    request_id: row.client_key, status: row.status, name: row.name,
    score_ids: JSON.parse(row.scores),
    ...(row.status === 'awaiting_approval' ? { approval_url: origin + '/approve/' + row.id } : {}),
    ...(row.status === 'saved' ? { setlist_id: 'assistant-' + row.id } : {}),
  });
  const revoke = id => {
    run('DELETE FROM requests WHERE grant_id = ?', id);
    run('DELETE FROM tokens WHERE grant_id = ?', id);
    run('DELETE FROM codes WHERE grant = ?', id);
    run('DELETE FROM grants WHERE id = ?', id);
  };
  function execute(grant, name, args) {
    if (!args || typeof args !== 'object' || Array.isArray(args)) {
      throw new RequestError(400, 'Expected a tool argument object');
    }
    const library = get('SELECT catalog, synced FROM libraries WHERE id = ?', grant.library);
    const snapshot = JSON.parse(library.catalog);
    if (name === 'search_scores' && text(args.query)) {
      const terms = args.query.toLowerCase().trim().split(/\s+/);
      return { scores: snapshot.scores.filter(s => terms.every(term => (s.title + ' ' + s.composer).toLowerCase().includes(term))).slice(0, 50),
        synced_at: library.synced == null ? null : new Date(library.synced).toISOString() };
    }
    if (name === 'list_setlists' && (args.offset === undefined || (Number.isSafeInteger(args.offset) && args.offset >= 0))) {
      const offset = args.offset ?? 0;
      return { setlists: snapshot.setlists.slice(offset, offset + 25),
        next_offset: offset + 25 < snapshot.setlists.length ? offset + 25 : null };
    }
    if (name === 'get_setlist_request' && writeScope(grant) && validId(args.request_id)) {
      const row = get('SELECT * FROM requests WHERE grant_id = ? AND client_key = ?', grant.id, args.request_id);
      if (row) return requestStatus(row);
      throw new RequestError(404, 'Request not found');
    }
    if (name === 'create_setlist' && writeScope(grant) && validId(args.request_id) && text(args.name) &&
        args.name.trim() && Array.isArray(args.score_ids) && args.score_ids.length > 0 &&
        args.score_ids.length <= 200 && args.score_ids.every(validId)) {
      const requestedName = args.name.trim();
      const ordered = JSON.stringify(args.score_ids);
      const existing = get('SELECT * FROM requests WHERE grant_id = ? AND client_key = ?', grant.id, args.request_id);
      if (existing) {
        if (existing.name !== requestedName || existing.scores !== ordered) {
          throw new RequestError(409, 'Request ID already used for a different setlist');
        }
        return requestStatus(existing);
      }
      const known = new Set(snapshot.scores.map(s => s.id));
      if (!args.score_ids.every(id => known.has(id))) throw new RequestError(400, 'Search for current score IDs first');
      const row = { id: secret(), client_key: args.request_id, name: requestedName,
        scores: ordered, status: 'awaiting_approval' };
      run('INSERT INTO requests VALUES (?, ?, ?, ?, ?, ?, ?)', row.id, grant.id,
        row.client_key, row.name, row.scores, row.status, now());
      return requestStatus(row);
    }
    throw new RequestError(400, 'Tool unavailable or invalid arguments');
  }

  return createServer(async (req, res) => {
    try {
      const url = new URL(req.url, origin);
      const path = url.pathname;
      const method = req.method;
      const bearer = req.headers.authorization?.match(/^Bearer ([a-zA-Z0-9_-]{43})$/i)?.[1];
      if (req.headers.origin && req.headers.origin !== origin) {
        return reply(res, 403, { error: 'Origin not allowed' });
      }

      if (method === 'GET' && ['/.well-known/oauth-protected-resource', '/.well-known/oauth-protected-resource/mcp'].includes(path)) {
        return reply(res, 200, { resource, authorization_servers: [origin], scopes_supported: scopes, bearer_methods_supported: ['header'] });
      }
      if (method === 'GET' && path === '/.well-known/oauth-authorization-server') {
        return reply(res, 200, { issuer: origin, authorization_endpoint: origin + '/authorize',
          token_endpoint: origin + '/token', registration_endpoint: origin + '/register',
          scopes_supported: scopes, response_types_supported: ['code'],
          grant_types_supported: ['authorization_code', 'refresh_token'],
          token_endpoint_auth_methods_supported: ['none'], code_challenge_methods_supported: ['S256'] });
      }

      if (method === 'POST' && path === '/register') {
        const data = await read(req);
        if (!Array.isArray(data.redirect_uris) || !data.redirect_uris.length || data.redirect_uris.length > 10 ||
            !data.redirect_uris.every(safeRedirect) || (data.token_endpoint_auth_method && data.token_endpoint_auth_method !== 'none')) {
          return reply(res, 400, { error: 'invalid_client_metadata' });
        }
        const id = secret();
        const name = text(data.client_name, 100) ? data.client_name : 'MCP assistant';
        run('INSERT INTO clients VALUES (?, ?, ?)', id, name, JSON.stringify(data.redirect_uris));
        return reply(res, 201, { client_id: id, client_name: name, redirect_uris: data.redirect_uris,
          token_endpoint_auth_method: 'none', grant_types: ['authorization_code', 'refresh_token'], response_types: ['code'] });
      }
      if (path === '/authorize' && method === 'GET') {
        run('DELETE FROM consent WHERE expires <= ?', now());
        run('DELETE FROM codes WHERE expires <= ?', now());
        run('DELETE FROM tokens WHERE expires <= ?', now());
        const params = Object.fromEntries(url.searchParams);
        const client = params.client_id && get('SELECT * FROM clients WHERE id = ?', params.client_id);
        const requested = (params.scope ?? scopes.join(' ')).split(/\s+/);
        if (!client || !JSON.parse(client.redirects).includes(params.redirect_uri) ||
            params.response_type !== 'code' || !tokenPattern.test(params.code_challenge ?? '') ||
            params.code_challenge_method !== 'S256' || (params.resource && params.resource !== resource) ||
            !requested.includes(scopes[0]) || requested.some(s => !scopes.includes(s))) {
          return page(res, 400, 'Invalid connection request', '<p>Start again from your assistant.</p>');
        }
        const ticket = secret();
        run('INSERT INTO consent VALUES (?, ?, ?)', hash(ticket), JSON.stringify({ ...params, requested }), now() + 10 * minute);
        const create = requested.includes(scopes[1])
          ? '<p><label><input type="checkbox" name="write" value="yes"> Allow requests to create setlists</label></p>' : '';
        return page(res, 200, 'Connect ' + client.name, '<p>This connection can search score metadata and read setlists.</p>' +
          '<form method="post" action="/authorize"><input type="hidden" name="ticket" value="' + ticket +
          '"><label>Connection code from EncoreSheets <input name="code" required autocomplete="off"></label>' +
          create + '<button>Connect assistant</button></form>', new URL(params.redirect_uri).origin);
      }
      if (path === '/authorize' && method === 'POST') {
        const form = await read(req, true);
        const ticket = get('SELECT * FROM consent WHERE id = ? AND expires > ?', hash(form.ticket ?? ''), now());
        const pairing = get('SELECT * FROM pairing WHERE code = ? AND expires > ?', hash(form.code?.trim() ?? ''), now());
        if (!ticket || !pairing) return page(res, 400, 'Connection code invalid or expired', '<p>Generate a new code in EncoreSheets, then go back and retry.</p>');
        const request = JSON.parse(ticket.request);
        const grant = secret();
        const code = secret();
        const browser = secret();
        const scope = form.write === 'yes' && request.requested.includes(scopes[1]) ? scopes.join(' ') : scopes[0];
        run('DELETE FROM consent WHERE id = ?', ticket.id);
        run('DELETE FROM pairing WHERE code = ?', pairing.code);
        run('INSERT INTO grants VALUES (?, ?, ?, ?, ?)', grant, pairing.library, request.client_id, scope, hash(browser));
        run('INSERT INTO codes VALUES (?, ?, ?, ?)', hash(code), grant, ticket.request, now() + 5 * minute);
        const redirect = new URL(request.redirect_uri);
        redirect.searchParams.set('code', code);
        if (request.state !== undefined) redirect.searchParams.set('state', request.state);
        return reply(res, 303, null, { Location: redirect.href,
          'Set-Cookie': 'es_' + grant + '=' + browser + '; HttpOnly; SameSite=Lax; Path=/approve; Max-Age=2592000' +
            (base.protocol === 'https:' ? '; Secure' : '') });
      }
      if (path === '/token' && method === 'POST') {
        const form = await read(req, true);
        let grant;
        const credential = form.grant_type === 'authorization_code' ? form.code : form.refresh_token;
        if (!credential || (form.resource && form.resource !== resource)) return reply(res, 400, { error: 'invalid_grant' });
        const key = hash(credential);
        if (form.grant_type === 'authorization_code') {
          const code = get('SELECT * FROM codes WHERE id = ? AND expires > ?', key, now());
          if (code) {
            const request = JSON.parse(code.request);
            if (request.client_id === form.client_id && request.redirect_uri === form.redirect_uri &&
                /^[A-Za-z0-9._~-]{43,128}$/.test(form.code_verifier ?? '') && hash(form.code_verifier) === request.code_challenge) {
              grant = get('SELECT * FROM grants WHERE id = ?', code.grant);
              run('DELETE FROM codes WHERE id = ?', key);
            }
          }
        } else if (form.grant_type === 'refresh_token') {
          grant = grantFor(credential, 'refresh');
          if (grant?.client !== form.client_id) grant = undefined;
          if (grant) run('DELETE FROM tokens WHERE id = ?', key);
        }
        if (!grant) return reply(res, 400, { error: 'invalid_grant' });
        const access = secret();
        const refresh = secret();
        run('INSERT INTO tokens VALUES (?, ?, ?, ?)', hash(access), grant.id, 'access', now() + 60 * minute);
        run('INSERT INTO tokens VALUES (?, ?, ?, ?)', hash(refresh), grant.id, 'refresh', now() + 30 * 24 * 60 * minute);
        return reply(res, 200, { access_token: access, token_type: 'Bearer', expires_in: 3600, refresh_token: refresh, scope: grant.scope });
      }

      if (path.startsWith('/approve/')) {
        const id = path.slice('/approve/'.length);
        const row = get('SELECT * FROM requests WHERE id = ?', id);
        const grant = row && browserGrant(req, row.grant_id);
        if (!grant) return page(res, 403, 'Open in your connection browser', '<p>Use the browser where you connected this assistant.</p>');
        if (row.status !== 'awaiting_approval') return page(res, 200, 'Setlist request', '<p>Status: ' + esc(row.status) + '</p>');
        const snapshot = JSON.parse(get('SELECT catalog FROM libraries WHERE id = ?', grant.library).catalog);
        const names = new Map(snapshot.scores.map(s => [s.id, s.title]));
        const ids = JSON.parse(row.scores);
        if (now() - row.created > 24 * 60 * minute || ids.some(id => !names.has(id))) {
          run("UPDATE requests SET status = 'rejected' WHERE id = ?", id);
          return page(res, 409, 'Request expired or scores unavailable', '<p>Ask your assistant to make a new request.</p>');
        }
        if (method === 'POST') {
          const form = await read(req, true);
          if (form.decision !== 'approve' && form.decision !== 'cancel') throw new RequestError(400, 'Invalid decision');
          const queued = form.decision === 'approve';
          const changed = run('UPDATE requests SET status = ? WHERE id = ? AND status = ?',
            queued ? 'queued' : 'canceled', id, 'awaiting_approval');
          if (!changed.changes) return page(res, 409, 'Request already handled', '<p>Refresh to check the current status.</p>');
          return page(res, 200, queued ? 'Setlist queued' : 'Request canceled',
            queued ? '<p>EncoreSheets will save it the next time your tablet syncs.</p>' : '');
        }
        if (method === 'GET') {
          return page(res, 200, 'Review ' + row.name, '<ol>' + ids.map(id => '<li>' + esc(names.get(id)) + '</li>').join('') +
            '</ol><form method="post"><button name="decision" value="approve">Create setlist</button> ' +
            '<button name="decision" value="cancel">Cancel</button></form>');
        }
      }

      if (path === '/mcp') {
        const grant = grantFor(bearer, 'access');
        if (!grant) return reply(res, 401, null, { 'WWW-Authenticate': 'Bearer resource_metadata="' + origin + '/.well-known/oauth-protected-resource/mcp"' });
        if (method !== 'POST') return reply(res, 405, null, { Allow: 'POST' });
        const message = await read(req);
        const id = message.id ?? null;
        const version = message.params?._meta?.['io.modelcontextprotocol/protocolVersion'];
        const result = value => reply(res, 200, { jsonrpc: '2.0', id, result:
          version ? { resultType: 'complete', ...value } : value });
        const error = (code, errorMessage, status = 200, data) =>
          reply(res, status, { jsonrpc: '2.0', id, error: { code, message: errorMessage, data } });
        if (message.jsonrpc !== '2.0' || typeof message.method !== 'string') return error(-32600, 'Invalid request');
        if (message.id === undefined && message.method.startsWith('notifications/')) return reply(res, 202, null);
        const params = message.params ?? {};
        const info = { name: 'encoresheets', title: 'EncoreSheets', version: '1.0.0' };
        const capabilities = { tools: {} };
        if (version !== undefined && version !== modernVersion) {
          return error(-32022, 'Unsupported protocol version', 400, {
            supported: [modernVersion, ...legacyVersions], requested: version,
          });
        }
        if (version) {
          const nameHeader = req.headers['mcp-name'];
          const encoded = typeof nameHeader === 'string' && nameHeader.match(/^=\?base64\?([A-Za-z0-9+/=]+)\?=$/);
          const name = encoded ? Buffer.from(encoded[1], 'base64').toString('utf8') : nameHeader;
          if (req.headers['mcp-protocol-version'] !== version ||
              req.headers['mcp-method'] !== message.method ||
              (message.method === 'tools/call' && name !== params.name)) {
            return error(-32600, 'MCP headers do not match the request', 400);
          }
        }
        if (message.method === 'server/discover' && version) {
          return result({ supportedVersions: [modernVersion, ...legacyVersions], capabilities,
            _meta: { 'io.modelcontextprotocol/serverInfo': info } });
        }
        if (message.method === 'initialize') return result({ protocolVersion: legacyVersions.includes(params.protocolVersion) ?
          params.protocolVersion : legacyVersions[0], capabilities, serverInfo: info });
        if (message.method === 'ping') return result({});
        if (message.method === 'tools/list') {
          return result({ tools: writeScope(grant) ? toolDefinitions : toolDefinitions.slice(0, 2) });
        }
        if (message.method === 'tools/call') {
          try {
            const content = execute(grant, params.name, params.arguments ?? {});
            return result({ content: [{ type: 'text', text: JSON.stringify(content) }] });
          } catch (err) {
            if (!(err instanceof RequestError)) throw err;
            return result({ isError: true, content: [{ type: 'text', text: err.message }] });
          }
        }
        return error(-32601, 'Method not found', version ? 404 : 200);
      }

      if (path === '/device/enroll' && method === 'POST') {
        if (!bearer || !timingSafeEqual(Buffer.from(hash(bearer)), Buffer.from(hash(enrollmentKey)))) {
          return reply(res, 401, { error: 'Invalid enrollment key' });
        }
        const token = secret();
        run('INSERT INTO libraries VALUES (?, ?, ?, NULL)', secret(), hash(token), JSON.stringify({ scores: [], setlists: [] }));
        return reply(res, 201, { token });
      }
      if (path.startsWith('/device/') && method === 'POST') {
        const library = bearer && get('SELECT * FROM libraries WHERE token = ?', hash(bearer));
        if (!library) return reply(res, 401, { error: 'Invalid tablet connection' });
        if (path === '/device/pair') {
          const code = secret();
          run('DELETE FROM pairing WHERE library = ? OR expires < ?', library.id, now());
          run('INSERT INTO pairing VALUES (?, ?, ?)', hash(code), library.id, now() + 10 * minute);
          return reply(res, 200, { code });
        }
        if (path === '/device/revoke') {
          const data = await read(req);
          if (!validId(data.id) || !get('SELECT id FROM grants WHERE library = ? AND id = ?', library.id, data.id)) {
            return reply(res, 404, { error: 'Connection not found' });
          }
          revoke(data.id);
          return reply(res, 200, {});
        }
        if (path === '/device/disconnect') {
          for (const grant of all('SELECT id FROM grants WHERE library = ?', library.id)) revoke(grant.id);
          run('DELETE FROM pairing WHERE library = ?', library.id);
          run('DELETE FROM libraries WHERE id = ?', library.id);
          return reply(res, 200, {});
        }
        if (path === '/device/sync') {
          const data = await read(req);
          if (!get('SELECT id FROM libraries WHERE id = ?', library.id)) {
            return reply(res, 401, { error: 'Invalid tablet connection' });
          }
          const snapshot = catalog(data);
          const receipts = data.receipts ?? {};
          if (!receipts || typeof receipts !== 'object' || Array.isArray(receipts) ||
              !Object.entries(receipts).every(([id, status]) => tokenPattern.test(id) && ['saved', 'rejected'].includes(status))) {
            throw new RequestError(400, 'Invalid receipts');
          }
          run('UPDATE libraries SET catalog = ?, synced = ? WHERE id = ?', JSON.stringify(snapshot), now(), library.id);
          for (const [id, status] of Object.entries(receipts)) {
            run("UPDATE requests SET status = ? WHERE id = ? AND status = 'queued' AND grant_id IN (SELECT id FROM grants WHERE library = ?)", status, id, library.id);
          }
          const pending = all("SELECT requests.* FROM requests JOIN grants ON grants.id = requests.grant_id WHERE library = ? AND requests.status = 'queued' ORDER BY created LIMIT 25", library.id)
            .map(row => ({ id: row.id, name: row.name, score_ids: JSON.parse(row.scores) }));
          const connections = all('SELECT grants.id, clients.name, scope FROM grants JOIN clients ON clients.id = grants.client WHERE library = ?', library.id);
          return reply(res, 200, { pending, connections });
        }
      }

      return reply(res, 404, { error: 'Not found' });
    } catch (err) {
      if (err instanceof RequestError) return reply(res, err.status, { error: err.message });
      console.error('EncoreSheets assistant request failed:', err.message);
      return reply(res, 500, { error: 'Internal server error' });
    }
  }).on('close', () => db.close());
}
