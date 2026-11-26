import { assistantServer } from './assistant_server.mjs';

const origin = process.env.ENCORESHEETS_ORIGIN ?? 'http://127.0.0.1:8787';
const enrollmentKey = process.env.ENCORESHEETS_ENROLLMENT_KEY;
if (!enrollmentKey) throw new Error('Set ENCORESHEETS_ENROLLMENT_KEY.');

if (process.argv[2] === 'enroll') {
  const response = await fetch(origin + '/device/enroll', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + enrollmentKey },
  });
  if (!response.ok) throw new Error('Tablet enrollment failed (' + response.status + ').');
  console.log((await response.json()).token);
} else {
  const server = assistantServer({
    origin,
    enrollmentKey,
    database: process.env.ENCORESHEETS_DB ?? 'assistant.sqlite',
  });
  const port = Number(process.env.PORT ?? 8787);
  const host = process.env.HOST ?? '127.0.0.1';
  server.listen(port, host, () => console.log('EncoreSheets MCP endpoint: ' + origin + '/mcp'));
}
