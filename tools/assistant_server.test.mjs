import assert from 'node:assert/strict';
import { createHash, randomBytes } from 'node:crypto';
import { createServer } from 'node:net';
import { test } from 'node:test';
import { assistantServer } from './assistant_server.mjs';

test('assistant grants, approval, offline queue, receipts and revocation', async t => {
  const probe = createServer();
  await new Promise(resolve => probe.listen(0, '127.0.0.1', resolve));
  const { port } = probe.address();
  await new Promise(resolve => probe.close(resolve));
  const origin = 'http://127.0.0.1:' + port;
  const enrollmentKey = randomBytes(32).toString('base64url');
  const server = assistantServer({ origin, database: ':memory:', enrollmentKey });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', resolve);
  });
  t.after(() => new Promise(resolve => server.close(resolve)));

  const post = (path, body = {}, token) => fetch(origin + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) },
    body: JSON.stringify(body),
  });
  const submit = (path, body, cookie) => fetch(origin + path, {
    method: 'POST', redirect: 'manual',
    headers: { Origin: origin, ...(cookie ? { Cookie: cookie } : {}) },
    body: new URLSearchParams(body),
  });
  const endpoint = await post('/mcp');
  assert.equal(endpoint.status, 401);
  assert.match(endpoint.headers.get('www-authenticate'), /oauth-protected-resource/);
  const { token } = await (await post('/device/enroll', {}, enrollmentKey)).json();
  const scores = [
    { id: 'bach', title: 'Cello Suite', composer: 'Bach', duration: '15:00', pdf: 'private' },
    { id: 'debussy', title: 'Arabesque', composer: 'Debussy', duration: '4:00' },
  ];
  const catalog = { scores, setlists: [] };
  const device = async (path, body) => (await post('/device/' + path, body, token)).json();
  assert.deepEqual((await device('sync', catalog)).pending, []);
  const connect = async (name, canWrite) => {
    const redirect = 'https://example.com/callback';
    const registration = await post('/register', { client_name: name, redirect_uris: [redirect] });
    assert.equal(registration.status, 201);
    const { client_id } = await registration.json();
    const verifier = randomBytes(32).toString('base64url');
    const challenge = createHash('sha256').update(verifier).digest('base64url');
    const params = new URLSearchParams({
      client_id, redirect_uri: redirect, response_type: 'code', code_challenge: challenge,
      code_challenge_method: 'S256', resource: origin + '/mcp', state: 'client-state',
    });
    const consent = await (await fetch(origin + '/authorize?' + params)).text();
    const ticket = consent.match(/name="ticket" value="([^"]+)/)[1];
    const { code } = await device('pair');
    const linked = await submit('/authorize', { ticket, code, write: canWrite ? 'yes' : 'no' });
    assert.equal(linked.status, 303);
    assert.equal((await submit('/authorize', { ticket, code })).status, 400);
    const returned = new URL(linked.headers.get('location')).searchParams;
    assert.equal(returned.get('state'), 'client-state');
    const args = { grant_type: 'authorization_code', client_id, redirect_uri: redirect, code: returned.get('code') };
    assert.equal((await submit('/token', { ...args, code_verifier: challenge })).status, 400);
    const tokens = await (await submit('/token', { ...args, code_verifier: verifier })).json();
    assert.ok(tokens.access_token);
    assert.equal((await submit('/token', { ...args, code_verifier: verifier })).status, 400);
    const refreshed = await (await submit('/token', {
      grant_type: 'refresh_token', client_id, refresh_token: tokens.refresh_token,
    })).json();
    assert.ok(refreshed.access_token);
    assert.equal((await submit('/token', {
      grant_type: 'refresh_token', client_id, refresh_token: tokens.refresh_token,
    })).status, 400);
    return [refreshed.access_token, linked.headers.get('set-cookie').split(';')[0]];
  };
  const [reader] = await connect('Read-only assistant', false);
  const [writer, cookie] = await connect('Writing assistant', true);
  const rpc = async (access, method, params = {}) =>
    (await post('/mcp', { jsonrpc: '2.0', id: 1, method, params }, access)).json();
  const tool = async (access, name, args) => (await rpc(access, 'tools/call', { name, arguments: args })).result;
  const unpack = result => JSON.parse(result.content[0].text);
  assert.equal((await rpc(writer, 'initialize', { protocolVersion: '2025-11-25' })).result.protocolVersion, '2025-11-25');
  const modern = await fetch(origin + '/mcp', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + writer,
      'MCP-Protocol-Version': '2026-07-28', 'Mcp-Method': 'server/discover' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'server/discover',
      params: { _meta: { 'io.modelcontextprotocol/protocolVersion': '2026-07-28' } } }),
  });
  const discovery = (await modern.json()).result;
  assert.equal(discovery.resultType, 'complete');
  assert.ok(discovery.supportedVersions.includes('2026-07-28'));
  assert.equal((await rpc(reader, 'tools/list')).result.tools.length, 2);
  assert.equal((await rpc(writer, 'tools/list')).result.tools.length, 4);
  assert.deepEqual(unpack(await tool(reader, 'search_scores', { query: 'bach' })).scores,
    [{ id: 'bach', title: 'Cello Suite', composer: 'Bach', duration: '15:00' }]);

  const input = { request_id: 'friday', name: 'Friday Rehearsal', score_ids: ['debussy', 'bach'] };
  assert.equal((await tool(reader, 'create_setlist', input)).isError, true);
  const draft = unpack(await tool(writer, 'create_setlist', input));
  assert.equal(draft.status, 'awaiting_approval');
  assert.deepEqual(unpack(await tool(writer, 'create_setlist', input)), draft);
  assert.equal((await tool(writer, 'create_setlist', { ...input, name: 'Different' })).isError, true);
  assert.deepEqual((await device('sync', catalog)).pending, []);
  const approvalPath = new URL(draft.approval_url).pathname;
  assert.equal((await submit(approvalPath, { decision: 'approve' })).status, 403);
  const preview = await (await fetch(draft.approval_url, { headers: { Cookie: cookie } })).text();
  assert.match(preview, /<li>Arabesque<\/li><li>Cello Suite<\/li>/);
  assert.equal((await submit(approvalPath, { decision: 'approve' }, cookie)).status, 200);
  assert.equal(unpack(await tool(writer, 'get_setlist_request', { request_id: 'friday' })).status, 'queued');
  const pending = await device('sync', catalog);
  assert.equal(pending.pending.length, 1);
  const [command] = pending.pending;
  assert.deepEqual(command.score_ids, input.score_ids);
  assert.deepEqual((await device('sync', catalog)).pending, pending.pending);
  const setlist = { id: 'assistant-' + command.id, name: command.name, score_ids: command.score_ids };
  const saved = await device('sync', { ...catalog, setlists: [setlist], receipts: { [command.id]: 'saved' } });
  assert.deepEqual(saved.pending, []);
  assert.equal(unpack(await tool(writer, 'get_setlist_request', { request_id: 'friday' })).status, 'saved');
  assert.deepEqual(unpack(await tool(reader, 'list_setlists', {})).setlists, [setlist]);

  const second = unpack(await tool(writer, 'create_setlist', { ...input, request_id: 'saturday' }));
  await submit(new URL(second.approval_url).pathname, { decision: 'approve' }, cookie);
  await device('revoke', { id: saved.connections.find(item => item.name === 'Writing assistant').id });
  assert.equal((await post('/mcp', {}, writer)).status, 401);
  assert.deepEqual((await device('sync', catalog)).pending, []);
  await device('disconnect');
  assert.equal((await post('/mcp', {}, reader)).status, 401);
});
