import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { createFixtureServer, isLoopback, VERSION, SYNTHETIC_CREDENTIAL } from './device-fixture-server.mjs';

async function withFixture(run, options = {}) {
  const fixture = createFixtureServer({ port: 0, ...options });
  const state = await fixture.listen();
  try { await run(fixture, `http://127.0.0.1:${state.address.port}`); }
  finally { await fixture.close(); }
}

function control(base, patch) {
  return fetch(`${base}/control`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(patch) });
}

test('localhost synthetic balance and control update without provider credentials', async () => {
  await withFixture(async (fixture, base) => {
    const initial = await fetch(`${base}/balance`, { headers: { Authorization: `Bearer ${SYNTHETIC_CREDENTIAL}` } });
    assert.equal(initial.status, 200);
    assert.deepEqual(await initial.json(), { balance: 100 });
    assert.equal((await control(base, { balance: 93.25 })).status, 200);
    assert.deepEqual(await (await fetch(`${base}/balance`)).json(), { balance: 93.25 });
    const status = await (await fetch(`${base}/status`)).json();
    assert.equal(status.version, VERSION);
    assert.equal(status.status, 'listening');
    assert.equal(status.counts.balanceRequests, 2);
    assert.equal(status.counts.controlUpdates, 1);
    assert.ok(!JSON.stringify(status).includes(SYNTHETIC_CREDENTIAL));
    assert.deepEqual(fixture.status().control, { balance: 93.25, httpStatus: 200, delayMs: 0 });
  });
});

test('controlled HTTP errors keep synthetic JSON and delayed requests use a snapshot', async () => {
  await withFixture(async (_fixture, base) => {
    await control(base, { balance: 10, httpStatus: 503, delayMs: 200 });
    const started = performance.now();
    const inFlight = fetch(`${base}/balance`);
    // Confirm the request has reached the fixture before changing the control.
    for (let attempt = 0; attempt < 40; attempt++) {
      const status = await (await fetch(`${base}/status`)).json();
      if (status.counts.balanceRequests === 1) break;
      await delay(5);
    }
    assert.equal((await (await fetch(`${base}/status`)).json()).counts.balanceRequests, 1);
    await control(base, { balance: 20, httpStatus: 200, delayMs: 0 });
    const response = await inFlight;
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { balance: 10 });
    assert.ok(performance.now() - started >= 175);
    assert.deepEqual(await (await fetch(`${base}/balance`)).json(), { balance: 20 });
  });
});

test('invalid controls cannot change balance or reflect request secrets', async () => {
  await withFixture(async (fixture, base) => {
    for (const patch of [{ balance: 'secret-value' }, { httpStatus: 204 }, { httpStatus: 99 }, { delayMs: -1 }, { delayMs: 60001 }, { unknown: SYNTHETIC_CREDENTIAL }, {}]) {
      const response = await control(base, patch);
      assert.equal(response.status, 400);
      assert.deepEqual(await response.json(), { error: 'invalid_control' });
    }
    const malformed = await fetch(`${base}/control`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: `{"secret":"${SYNTHETIC_CREDENTIAL}` });
    assert.equal(malformed.status, 400);
    assert.ok(!(await malformed.text()).includes(SYNTHETIC_CREDENTIAL));
    const oversized = await fetch(`${base}/control`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: 'x'.repeat(2049) });
    assert.equal(oversized.status, 413);
    const wrongType = await fetch(`${base}/control`, { method: 'POST', body: '{}' });
    assert.equal(wrongType.status, 415);
    assert.deepEqual(fixture.status().control, { balance: 100, httpStatus: 200, delayMs: 0 });
    assert.equal(fixture.status().counts.controlUpdates, 0);
  });
});

test('loopback restriction, unknown paths, and incorrect methods', async () => {
  assert.ok(isLoopback('127.0.0.1'));
  assert.ok(isLoopback('::1'));
  assert.ok(isLoopback('::ffff:127.0.0.1'));
  for (const remote of ['192.168.1.1', '0.0.0.0', '::', '127.evil.example', undefined]) assert.equal(isLoopback(remote), false);
  assert.throws(() => createFixtureServer({ host: '0.0.0.0' }), /loopback/);
  await withFixture(async (_fixture, base) => {
    assert.equal((await fetch(`${base}/missing`)).status, 404);
    const incorrectMethod = await fetch(`${base}/control`);
    assert.equal(incorrectMethod.status, 405);
    assert.equal(incorrectMethod.headers.get('allow'), 'POST');
  });
});

test('occupied port makes the executable exit nonzero without choosing another port', async () => {
  await withFixture(async (fixture) => {
    const port = fixture.status().address.port;
    const filename = fileURLToPath(new URL('./device-fixture-server.mjs', import.meta.url));
    const child = spawn(process.execPath, [filename, '--port', String(port)], { stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '';
    child.stdout.on('data', (chunk) => { output += chunk; });
    child.stderr.on('data', (chunk) => { output += chunk; });
    const code = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => { child.kill(); reject(new Error('Fixture CLI did not exit on a port conflict.')); }, 5000);
      child.once('error', (error) => { clearTimeout(timer); reject(error); });
      child.once('exit', (exitCode) => { clearTimeout(timer); resolve(exitCode); });
    });
    assert.equal(code, 1);
    assert.match(output, /EADDRINUSE/);
    assert.ok(!output.includes('"status":"listening"'));
  });
});
