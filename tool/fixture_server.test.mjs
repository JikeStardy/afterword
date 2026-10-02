import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';

test('device fixture supports source summaries and preserves supplied PDF evidence', { timeout: 10000 }, async (t) => {
  const child = spawn(process.execPath, ['tool/fixture_server.mjs'], {
    env: { ...process.env, READLATER_FIXTURE_PORT: '0' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  t.after(async () => {
    if (child.exitCode === null) {
      const exited = once(child, 'exit');
      child.kill();
      await exited;
    }
  });
  const ready = await new Promise((resolve, reject) => {
    let output = '';
    child.on('error', reject);
    child.once('exit', (code) => reject(new Error(`Fixture exited before ready: ${code}`)));
    child.stdout.on('data', (data) => {
      output += data;
      const match = output.match(/127\.0\.0\.1:(\d+)/);
      if (match) resolve(`http://127.0.0.1:${match[1]}`);
    });
  });
  async function complete(prompt) {
    const response = await fetch(`${ready}/v1/chat/completions`, {
      method: 'POST',
      headers: { authorization: 'Bearer fixture-key', 'content-type': 'application/json' },
      body: JSON.stringify({ messages: [{ role: 'user', content: prompt }] }),
    });
    assert.equal(response.status, 200);
    return JSON.parse((await response.json()).choices[0].message.content);
  }
  for (const task of ['summarize_source_segment', 'summarize_pdf_pages', 'merge_source_segment_summaries']) {
    assert.ok((await complete(JSON.stringify({ task }))).summary);
  }
  const evidence = { sourceId: 'pdf', sourceVersion: 2, pdfPage: 1, assetFingerprint: 'fixture-fingerprint', quote: '', unresolved: true };
  const input = { item: { id: 'pdf', contentVersion: 2, contentBlocks: [] }, related: [], availableEvidence: [evidence] };
  const result = await complete(`生成观点卡片\n输入数据：${JSON.stringify(input)}`);
  assert.deepEqual(result.structuredInsights[0].evidence, [evidence]);
  input.availableEvidence = [];
  assert.deepEqual((await complete(`生成观点卡片\n输入数据：${JSON.stringify(input)}`)).structuredInsights, []);
});
