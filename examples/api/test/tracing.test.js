import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { setTimeout as sleep } from 'node:timers/promises';

const appDir = fileURLToPath(new URL('..', import.meta.url));
const SPAN_KIND_SERVER = 2;

const spans = [];
const collector = http.createServer((req, res) => {
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    if (req.method === 'POST' && req.url === '/v1/traces') {
      const body = JSON.parse(Buffer.concat(chunks).toString());
      for (const rs of body.resourceSpans ?? []) {
        for (const ss of rs.scopeSpans ?? []) spans.push(...(ss.spans ?? []));
      }
    }
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end('{}');
  });
});

let child;
let childExited = false;
let childOutput = '';

after(async () => {
  if (child && !childExited) {
    try { process.kill(-child.pid, 'SIGTERM'); } catch {}
    for (let i = 0; i < 60 && !childExited; i++) await sleep(50);
  }
  if (child) {
    try { process.kill(-child.pid, 'SIGKILL'); } catch {}
    child.stdout.destroy();
    child.stderr.destroy();
  }
  collector.closeAllConnections();
  await new Promise((resolve) => collector.close(resolve));
});

function freePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.on('error', reject);
    srv.listen(0, '127.0.0.1', () => {
      const { port } = srv.address();
      srv.close(() => resolve(port));
    });
  });
}

function findRequestTrace() {
  const server = spans.filter((s) => s.kind === SPAN_KIND_SERVER && s.name === 'GET /hello');
  if (server.length === 0) return null;
  const { traceId } = server[0];
  const inTrace = spans.filter((s) => s.traceId === traceId);
  const ready =
    inTrace.some((s) => s.name === 'request handler - /hello') &&
    inTrace.some((s) => s.name === 'parse json');
  return ready ? traceId : null;
}

test('npm start traces GET /hello with server, Express and manual spans', async () => {
  await new Promise((resolve) => collector.listen(0, '127.0.0.1', resolve));
  const collectorUrl = `http://127.0.0.1:${collector.address().port}`;
  const port = await freePort();

  child = spawn('npm', ['start'], {
    cwd: appDir,
    detached: true,
    stdio: ['ignore', 'pipe', 'pipe'],
    env: {
      PATH: process.env.PATH,
      HOME: process.env.HOME,
      PORT: String(port),
      TEMPO_URL: collectorUrl,
      LOKI_URL: collectorUrl,
      TEMPO_SERVICE_NAME: 'example-api-test',
      OTEL_BSP_SCHEDULE_DELAY: '100',
    },
  });
  child.stdout.on('data', (d) => (childOutput += d));
  child.stderr.on('data', (d) => (childOutput += d));
  child.on('exit', () => (childExited = true));

  let response;
  const startDeadline = Date.now() + 10_000;
  while (!response) {
    assert.ok(!childExited, `npm start exited before serving:\n${childOutput}`);
    assert.ok(Date.now() < startDeadline, `app never answered on port ${port}:\n${childOutput}`);
    try {
      response = await fetch(`http://127.0.0.1:${port}/hello`, {
        signal: AbortSignal.timeout(Math.max(1, startDeadline - Date.now())),
      });
    } catch (err) {
      assert.notEqual(err.name, 'TimeoutError', `app never answered on port ${port}:\n${childOutput}`);
      await sleep(50);
    }
  }
  assert.equal(response.status, 200);
  await response.text();

  let traceId = null;
  const spanDeadline = Date.now() + 10_000;
  while (!traceId && Date.now() < spanDeadline) {
    traceId = findRequestTrace();
    if (!traceId) await sleep(100);
  }

  const received = spans.map((s) => `${s.name} (kind ${s.kind})`);
  const serverSpans = spans.filter((s) => s.kind === SPAN_KIND_SERVER && s.name === 'GET /hello');
  assert.equal(serverSpans.length, 1, `expected one server span "GET /hello"; received: ${JSON.stringify(received)}`);

  const [serverSpan] = serverSpans;
  const trace = spans.filter((s) => s.traceId === serverSpan.traceId);
  assert.ok(
    trace.some((s) => s.name === 'request handler - /hello'),
    `expected Express span "request handler - /hello" in the request trace; received: ${JSON.stringify(received)}`,
  );

  const manual = spans.filter((s) => s.name === 'parse json');
  assert.equal(manual.length, 1, `expected one "parse json" span; received: ${JSON.stringify(received)}`);
  assert.equal(manual[0].traceId, serverSpan.traceId, '"parse json" is not in the GET /hello trace');

  const byId = new Map(trace.map((s) => [s.spanId, s]));
  let ancestor = byId.get(manual[0].parentSpanId);
  while (ancestor && ancestor.spanId !== serverSpan.spanId) ancestor = byId.get(ancestor.parentSpanId);
  assert.ok(ancestor, '"GET /hello" is not an ancestor of "parse json"');
});
