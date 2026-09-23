import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { mkdtemp, rm, readdir, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { createDiagnosticReceiver } from './diagnostics_receiver.mjs';

const token = 'fixture-only-receiver-token';
const id = 'report_0123456789';
const body = Buffer.from('PK\x03\x04 fixture archive bytes');
async function fixture(t, options = {}) {
  const root = await mkdtemp(path.join(tmpdir(), 'readlater-receiver-'));
  const output = path.join(root, 'reports');
  const server = createDiagnosticReceiver({ token, output, ...options });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => { server.closeAllConnections(); await new Promise((resolve) => server.close(resolve)); await rm(root, { recursive: true, force: true }); });
  return { server, root, output, port: server.address().port };
}
function upload(port, { reportId = id, data = body, headers = {}, chunked = false } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({ hostname: '127.0.0.1', port, path: '/diagnostics', method: 'POST', headers: {
      authorization: `Bearer ${token}`, 'content-type': 'application/zip', 'x-report-id': reportId,
      ...(chunked ? {} : { 'content-length': data.length }), ...headers,
    } }, (res) => { const chunks = []; res.on('data', (chunk) => chunks.push(chunk)); res.on('end', () => resolve({ status: res.statusCode, json: JSON.parse(Buffer.concat(chunks)) })); });
    req.on('error', reject);
    if (chunked) req.write(data);
    req.end(chunked ? undefined : data);
  });
}
async function noTemporary(output) {
  for (let i = 0; i < 100; i++) {
    const names = await readdir(output).catch(() => []);
    if (!names.some((name) => name.startsWith('.incoming-'))) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  assert.fail('partial upload was not removed');
}

test('stores exact bytes, reports checksum and retries idempotently', async (t) => {
  const { port, output } = await fixture(t);
  const first = await upload(port);
  assert.equal(first.status, 201);
  assert.deepEqual(first.json, { reportId: id, bytes: body.length, sha256: createHash('sha256').update(body).digest('hex') });
  assert.deepEqual(await readFile(path.join(output, `${id}.zip`)), body);
  assert.equal((await upload(port)).status, 200);
  assert.equal((await upload(port, { data: Buffer.from('different') })).status, 409);
  await noTemporary(output);
});
test('authentication, IDs, content type and empty uploads fail without persistence', async (t) => {
  const { port, output } = await fixture(t);
  assert.equal((await upload(port, { headers: { authorization: 'Bearer wrong' } })).status, 401);
  for (const reportId of ['../outside', 'short', 'x'.repeat(81), 'validlength/badpath']) assert.equal((await upload(port, { reportId })).status, 400);
  assert.equal((await upload(port, { headers: { 'content-type': 'text/plain' } })).status, 415);
  assert.equal((await upload(port, { data: Buffer.alloc(0) })).status, 400);
  await noTemporary(output);
  assert.deepEqual(await readdir(output), []);
});
test('rejects declared and chunked oversize uploads', async (t) => {
  const { port, output } = await fixture(t, { maxBytes: 8 });
  assert.equal((await upload(port)).status, 413);
  assert.equal((await upload(port, { chunked: true })).status, 413);
  await noTemporary(output);
  assert.deepEqual(await readdir(output), []);
});
test('concurrent identical retries create only one report', async (t) => {
  const { port, output } = await fixture(t);
  const results = await Promise.all(Array.from({ length: 8 }, () => upload(port)));
  assert.equal(results.filter((r) => r.status === 201).length, 1);
  assert.equal(results.filter((r) => r.status === 200).length, 7);
  await noTemporary(output);
  assert.deepEqual(await readdir(output), [`${id}.zip`]);
});
test('concurrent conflicting content never replaces the winner', async (t) => {
  const { port, output } = await fixture(t);
  const alternate = Buffer.from('PK alternate archive');
  const results = await Promise.all([upload(port), upload(port, { data: alternate })]);
  assert.deepEqual(results.map((r) => r.status).sort(), [201, 409]);
  const winner = results.findIndex((r) => r.status === 201);
  assert.deepEqual(await readFile(path.join(output, `${id}.zip`)), winner === 0 ? body : alternate);
  await noTemporary(output);
});
test('disconnected upload removes partial file', async (t) => {
  const { port, output } = await fixture(t);
  const req = http.request({ hostname: '127.0.0.1', port, path: '/diagnostics', method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/zip', 'x-report-id': id, 'content-length': 10000 } });
  req.on('error', () => {});
  req.write(body);
  for (let i = 0; i < 100; i++) {
    if ((await readdir(output).catch(() => [])).length) break;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  req.destroy();
  await noTemporary(output);
  assert.deepEqual(await readdir(output), []);
});
test('disk failure has bounded error and no success receipt', async (t) => {
  const { port, output } = await fixture(t);
  await writeFile(output, 'not a directory');
  const result = await upload(port);
  assert.equal(result.status, 500);
  assert.deepEqual(result.json, { error: 'upload_failed' });
});
test('refuses missing token and invalid limits at startup', () => {
  assert.throws(() => createDiagnosticReceiver());
  assert.throws(() => createDiagnosticReceiver({ token, maxBytes: 0 }));
});
