import http from 'node:http';
import { createHash, timingSafeEqual, randomUUID } from 'node:crypto';
import { open, mkdir, link, unlink, lstat } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const digest = (value) => createHash('sha256').update(value).digest();
const maxUploadBytes = 64 * 1024 * 1024;

async function fileDigest(file) {
  const stat = await lstat(file);
  if (!stat.isFile()) throw new Error('Not a regular report');
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(file)) hash.update(chunk);
  return { bytes: stat.size, sha256: hash.digest('hex') };
}

// No report contents, credentials, request headers or private URLs are logged.
export function createDiagnosticReceiver({ token, output = 'dist/diagnostics', maxBytes = maxUploadBytes } = {}) {
  if (typeof token !== 'string' || !token.trim() || token.length > 4096 || /[\r\n]/.test(token)) {
    throw new Error('READLATER_DIAGNOSTIC_TOKEN must be a nonempty token of at most 4096 characters');
  }
  if (!Number.isSafeInteger(maxBytes) || maxBytes < 1 || maxBytes > maxUploadBytes) throw new Error('Invalid upload limit');
  const credential = digest(`Bearer ${token}`);
  const directory = path.resolve(output);
  const server = http.createServer({ maxHeaderSize: 8192, requestTimeout: 120000, headersTimeout: 15000 }, async (req, res) => {
    let temporary;
    let handle;
    const reply = (status, body) => {
      if (res.destroyed || res.writableEnded) return;
      res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store', connection: 'close' });
      res.end(JSON.stringify(body));
      req.resume();
    };
    try {
      if (req.method !== 'POST' || req.url !== '/diagnostics') return reply(404, { error: 'not_found' });
      if (!timingSafeEqual(digest(req.headers.authorization ?? ''), credential)) return reply(401, { error: 'unauthorized' });
      const reportId = req.headers['x-report-id'];
      if (typeof reportId !== 'string' || !/^[a-zA-Z0-9_-]{16,80}$/.test(reportId)) return reply(400, { error: 'invalid_report_id' });
      if (req.headers['content-type']?.split(';')[0].trim().toLowerCase() !== 'application/zip') return reply(415, { error: 'expected_zip' });
      if (req.headers['content-encoding'] && req.headers['content-encoding'] !== 'identity') return reply(415, { error: 'unsupported_encoding' });
      if (Number(req.headers['content-length']) > maxBytes) return reply(413, { error: 'too_large' });
      await mkdir(directory, { recursive: true, mode: 0o700 });
      temporary = path.join(directory, `.incoming-${randomUUID()}`);
      handle = await open(temporary, 'wx', 0o600);
      let bytes = 0;
      const hash = createHash('sha256');
      // Keep the socket alive long enough to return 413 for chunked requests.
      for await (const chunk of req.iterator({ destroyOnReturn: false })) {
        bytes += chunk.length;
        if (bytes > maxBytes) return reply(413, { error: 'too_large' });
        hash.update(chunk);
        let offset = 0;
        while (offset < chunk.length) {
          const result = await handle.write(chunk, offset, chunk.length - offset);
          if (result.bytesWritten === 0) throw new Error('Incomplete write');
          offset += result.bytesWritten;
        }
      }
      if (!req.complete) throw new Error('Incomplete request');
      if (!bytes) return reply(400, { error: 'empty_report' });
      await handle.sync();
      await handle.close();
      handle = undefined;
      const sha256 = hash.digest('hex');
      const destination = path.join(directory, `${reportId}.zip`);
      let status = 201;
      try {
        // An exclusive hard link publishes the complete file atomically. Unlike
        // rename, it cannot overwrite a simultaneous upload with the same ID.
        await link(temporary, destination);
      } catch (error) {
        if (error.code !== 'EEXIST') throw error;
        const existing = await fileDigest(destination);
        if (existing.bytes !== bytes || existing.sha256 !== sha256) return reply(409, { error: 'report_id_conflict' });
        status = 200;
      }
      reply(status, { reportId, bytes, sha256 });
    } catch {
      reply(500, { error: 'upload_failed' });
    } finally {
      await handle?.close().catch(() => console.warn('Diagnostic receiver could not close a temporary report'));
      if (temporary) await unlink(temporary).catch((error) => {
        if (error.code !== 'ENOENT') console.warn('Diagnostic receiver could not remove a temporary report');
      });
    }
  });
  server.maxHeadersCount = 32;
  server.setTimeout(30000, (socket) => socket.destroy());
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    const options = { host: '127.0.0.1', port: 18766, output: 'dist/diagnostics' };
    for (let i = 2; i < process.argv.length; i += 2) {
      const flag = process.argv[i];
      const value = process.argv[i + 1];
      if (!['--host', '--port', '--output'].includes(flag) || !value) throw new Error('Usage: node tool/diagnostics_receiver.mjs [--host ADDRESS] [--port PORT] [--output DIRECTORY]');
      options[flag.slice(2)] = flag === '--port' ? Number(value) : value;
    }
    if (!Number.isInteger(options.port) || options.port < 1 || options.port > 65535) throw new Error('Invalid port');
    const server = createDiagnosticReceiver({ token: process.env.READLATER_DIAGNOSTIC_TOKEN, output: options.output });
    server.on('error', () => { console.error('Receiver failed to listen'); process.exitCode = 1; });
    server.listen(options.port, options.host, () => console.log(`Diagnostic receiver listening on ${options.host}:${options.port}; output: ${path.resolve(options.output)}`));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
