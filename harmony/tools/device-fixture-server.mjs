#!/usr/bin/env node
// Development fixture only. It never calls a provider or logs request data.
import { createServer } from 'node:http';
import { isIP } from 'node:net';
import { pathToFileURL } from 'node:url';

export const VERSION = '1.0.0';
export const SYNTHETIC_CREDENTIAL = 'synthetic-device-validation';
const DEFAULT_PORT = 41727;
const MAX_BODY_BYTES = 2048;
const MAX_DELAY_MS = 60000;

export function isLoopback(address) {
  const normalized = String(address ?? '').toLowerCase();
  if (normalized === '::1') return true;
  const ipv4 = normalized.startsWith('::ffff:') ? normalized.slice(7) : normalized;
  return isIP(ipv4) === 4 && ipv4.startsWith('127.');
}

function validateControl(patch) {
  if (!patch || typeof patch !== 'object' || Array.isArray(patch)) {
    throw new Error('Control must be a JSON object.');
  }
  const keys = Object.keys(patch);
  if (keys.length === 0 || keys.some((key) => !['balance', 'httpStatus', 'delayMs'].includes(key))) {
    throw new Error('Only balance, httpStatus and delayMs can be changed.');
  }
  if ('balance' in patch && (typeof patch.balance !== 'number' || !Number.isFinite(patch.balance))) {
    throw new Error('balance must be a finite number.');
  }
  if ('httpStatus' in patch && (!Number.isInteger(patch.httpStatus) || patch.httpStatus < 200 || patch.httpStatus > 599 || [204, 205, 304].includes(patch.httpStatus))) {
    throw new Error('httpStatus must be 200..599 and allow a JSON response body.');
  }
  if ('delayMs' in patch && (!Number.isInteger(patch.delayMs) || patch.delayMs < 0 || patch.delayMs > MAX_DELAY_MS)) {
    throw new Error(`delayMs must be an integer from 0 to ${MAX_DELAY_MS}.`);
  }
}

function sendJson(response, status, value, extraHeaders = {}) {
  if (response.destroyed || response.writableEnded) return;
  const body = JSON.stringify(value);
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
    ...extraHeaders,
  });
  response.end(body);
}

function readControl(request) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    let failed = false;
    request.on('data', (chunk) => {
      if (failed) return;
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        failed = true;
        chunks.length = 0;
        reject({ status: 413, code: 'control_too_large' });
      } else {
        chunks.push(chunk);
      }
    });
    request.on('end', () => {
      if (failed) return;
      try {
        const patch = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        validateControl(patch);
        resolve(patch);
      } catch {
        // Never return parser exceptions: they may include the request body.
        reject({ status: 400, code: 'invalid_control' });
      }
      chunks.length = 0;
    });
    request.on('error', () => reject({ status: 400, code: 'incomplete_control' }));
    request.on('aborted', () => reject({ status: 400, code: 'incomplete_control' }));
  });
}

export function createFixtureServer(options = {}) {
  const host = options.host ?? '127.0.0.1';
  const port = options.port ?? DEFAULT_PORT;
  if (!['127.0.0.1', '::1', 'localhost'].includes(host)) {
    throw new Error('The fixture can bind only to a loopback host.');
  }
  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    throw new Error('port must be an integer from 0 to 65535.');
  }
  let control = { balance: options.balance ?? 100, httpStatus: options.httpStatus ?? 200, delayMs: options.delayMs ?? 0 };
  validateControl(control);
  const counts = { balanceRequests: 0, controlUpdates: 0 };
  const pending = new Map();
  const status = () => ({
    name: 'balance-widget-device-fixture',
    version: VERSION,
    status: server.listening ? 'listening' : 'stopped',
    address: server.address() ? { host, port: server.address().port } : null,
    control: { ...control },
    counts: { ...counts },
  });
  const server = createServer(async (request, response) => {
    let pathname;
    try {
      pathname = new URL(request.url, 'http://127.0.0.1').pathname;
    } catch {
      sendJson(response, 400, { error: 'invalid_path' });
      return;
    }
    if (pathname === '/status' && request.method === 'GET') {
      sendJson(response, 200, status());
      return;
    }
    if (pathname === '/balance' && request.method === 'GET') {
      counts.balanceRequests += 1;
      // An in-flight request uses a snapshot, even if control changes later.
      const snapshot = { ...control };
      if (snapshot.delayMs === 0) {
        sendJson(response, snapshot.httpStatus, { balance: snapshot.balance });
      } else {
        const timer = setTimeout(() => {
          pending.delete(timer);
          sendJson(response, snapshot.httpStatus, { balance: snapshot.balance });
        }, snapshot.delayMs);
        pending.set(timer, response);
        response.once('close', () => { clearTimeout(timer); pending.delete(timer); });
      }
      return;
    }
    if (pathname === '/control' && request.method === 'POST') {
      if (!isLoopback(request.socket.remoteAddress)) {
        request.resume();
        sendJson(response, 403, { error: 'loopback_required' });
        return;
      }
      if (!/^application\/json(?:\s*;|\s*$)/i.test(request.headers['content-type'] ?? '')) {
        request.resume();
        sendJson(response, 415, { error: 'json_required' });
        return;
      }
      try {
        const patch = await readControl(request);
        control = { ...control, ...patch };
        counts.controlUpdates += 1;
        sendJson(response, 200, status());
      } catch (failure) {
        sendJson(response, failure.status ?? 400, { error: failure.code ?? 'invalid_control' });
      }
      return;
    }
    const allowedMethod = pathname === '/control' ? 'POST' : 'GET';
    if (['/balance', '/status', '/control'].includes(pathname)) {
      request.resume();
      sendJson(response, 405, { error: 'method_not_allowed' }, { Allow: allowedMethod });
    } else {
      request.resume();
      sendJson(response, 404, { error: 'not_found' });
    }
  });
  server.requestTimeout = 5000;
  server.headersTimeout = 5000;
  server.on('clientError', (_error, socket) => {
    if (socket.writable) socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
  });
  let closePromise;
  return {
    server,
    status,
    listen: () => new Promise((resolve, reject) => {
      const onError = (error) => reject(error);
      server.once('error', onError);
      server.listen(port, host, () => { server.off('error', onError); resolve(status()); });
    }),
    close: () => {
      if (!closePromise) {
        for (const [timer, response] of pending) {
          clearTimeout(timer);
          sendJson(response, 503, { error: 'fixture_stopping' });
        }
        pending.clear();
        closePromise = new Promise((resolve) => {
          if (!server.listening) { resolve(); return; }
          server.close(() => resolve());
          server.closeIdleConnections();
        });
      }
      return closePromise;
    },
  };
}

async function main(args) {
  if (args.includes('--version')) { console.log(VERSION); return; }
  if (args.includes('--help')) {
    console.log('Device fixture: --host 127.0.0.1 --port 41727 --balance 100 --http-status 200 --delay-ms 0');
    console.log('GET /balance; GET /status; localhost POST /control with balance/httpStatus/delayMs.');
    return;
  }
  const flags = { '--host': 'host', '--port': 'port', '--balance': 'balance', '--http-status': 'httpStatus', '--delay-ms': 'delayMs' };
  const options = {};
  for (let index = 0; index < args.length; index += 2) {
    const field = flags[args[index]];
    if (!field || index + 1 >= args.length) throw new Error('Invalid arguments; use --help.');
    options[field] = field === 'host' ? args[index + 1] : Number(args[index + 1]);
  }
  const fixture = createFixtureServer(options);
  const listening = await fixture.listen();
  console.log(JSON.stringify(listening));
  let stopping = false;
  const stop = async () => {
    if (stopping) return;
    stopping = true;
    await fixture.close();
    console.log(JSON.stringify({ name: listening.name, version: VERSION, status: 'stopped' }));
  };
  process.once('SIGINT', stop);
  process.once('SIGTERM', stop);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).catch((error) => {
    // The code is sufficient to diagnose port conflicts without dumping inputs.
    console.error(`Fixture startup failed: ${error.code ?? 'INVALID_CONFIGURATION'}.`);
    process.exitCode = 1;
  });
}
