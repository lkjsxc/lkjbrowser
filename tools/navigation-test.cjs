// Deterministic native navigation tests. Use --wayland for the private compositor proof.
'use strict';
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } = require('node:fs');
const http = require('node:http');
const net = require('node:net');
const { join, resolve } = require('node:path');
const tls = require('node:tls');
const { setTimeout: delay } = require('node:timers/promises');

process.chdir(resolve(__dirname, '..'));
const run = mkdtempSync(resolve('target/navigation-test-'));
const root = resolve('tests/x509/root.pem');
const browser = resolve('target/lkjbrowser');
const children = [];
const servers = [];
const sockets = new Set();

function launch(command, args, options = {}) {
  const process = spawn(command, args, options);
  const job = { process, log: '' };
  children.push(job);
  for (const stream of [process.stdout, process.stderr]) stream.on('data', (buf) => { job.log += buf; });
  job.done = new Promise((accept) => {
    process.once('error', (error) => { job.log += error.message; accept(-1); });
    process.once('close', (code) => accept(code));
  });
  return job;
}

async function until(check, label, limit = 3500) {
  const deadline = performance.now() + limit;
  while (performance.now() < deadline) {
    if (check()) return;
    await delay(20);
  }
  throw new Error('Timed out waiting for ' + label);
}

async function successful(job) {
  assert.equal(await job.done, 0, job.log);
}

function listen(server) {
  servers.push(server);
  server.on('connection', (socket) => {
    sockets.add(socket);
    socket.on('error', () => {});
    socket.on('close', () => sockets.delete(socket));
  });
  return new Promise((accept, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => accept(server.address().port));
  });
}

function page(response, title, extra = '') {
  response.writeHead(200, { 'Content-Type': 'text/html' });
  response.end('<title>' + title + '</title><h1>' + title + '</h1>' + extra);
}

async function phases() {
  // Linux allows one more completed connection than listen(backlog), then drops
  // new SYNs when the local listener never accepts. Prove the queue is full first.
  const backlog = launch('python3', ['-u', '-c', `
import socket, time
server = socket.socket()
server.bind(("127.0.0.1", 0))
server.listen(1)
address = server.getsockname()
clients = [socket.create_connection(address, 1) for _ in range(2)]
try:
    socket.create_connection(address, 0.25)
    raise AssertionError("backlog did not stall")
except TimeoutError:
    pass
print(address[1])
time.sleep(20)
`]);
  await until(() => /^\d+\n$/.test(backlog.log), 'saturated loopback backlog');
  const tlsSilent = await listen(net.createServer((socket) => socket.on('data', () => {})));
  const sni = await listen(net.createServer((socket) => {
    socket.once('data', () => socket.end(Buffer.from([21, 3, 3, 0, 2, 2, 112])));
  }));
  const httpSlow = await listen(http.createServer((request, response) => {
    response.writeHead(200, { 'Content-Type': 'text/html', 'Content-Length': '200' });
    response.write('<title>This partial page must stay hidden</title>');
  }));

  const tlsThenHttp = tls.createServer({
    key: readFileSync('tests/x509/localhost.key'),
    cert: readFileSync('tests/x509/localhost.pem'),
    minVersion: 'TLSv1.3', maxVersion: 'TLSv1.3',
  }, (socket) => {
    socket.once('data', async () => {
      await delay(3300, undefined, { ref: false });
      const body = '<title>Both stages completed</title>';
      socket.end('HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: ' + body.length + '\r\n\r\n' + body);
    });
  });
  const tlsDelayed = await listen(net.createServer({ pauseOnConnect: true }, async (socket) => {
    await delay(3300, undefined, { ref: false });
    if (!socket.destroyed) tlsThenHttp.emit('connection', socket);
  }));

  const cases = [
    ['connect', 'http://127.0.0.1:' + backlog.log.trim(), 'TCP connection deadline exceeded', 4900, 6800],
    ['tls', 'https://localhost:' + tlsSilent, 'TLS handshake deadline exceeded', 5900, 7800],
    ['http', 'http://127.0.0.1:' + httpSlow, 'HTTP response deadline exceeded', 5900, 7800],
    ['sni', 'https://localhost:' + sni, 'The server does not recognize this hostname', 0, 1500],
    ['separate', 'https://localhost:' + tlsDelayed, null, 6400, 9500],
  ];
  await Promise.all(cases.map(async ([name, url, reason, min, max]) => {
    const layout = join(run, name + '.layout');
    const job = launch('timeout', ['12s', browser, '--headless', '--width', '480', '--height', '320',
      '--trust-file', root, '--layout', layout, url + '/']);
    await successful(job);
    writeFileSync(join(run, name + '.log'), job.log);
    const text = readFileSync(layout, 'utf8');
    const elapsed = Number(job.log.match(/^PAINT headless elapsed_us=(\d+)/m)?.[1]) / 1000;
    assert(elapsed >= min && elapsed < max, name + ' elapsed ' + elapsed + ' ms');
    assert(text.includes('URL ' + url + '/\n'));
    if (reason) {
      assert(job.log.includes('NAV_ERROR ' + url + '/: ' + reason), job.log);
      assert(text.includes('TITLE Unable to open this page\n'));
      const words = Array.from(text.matchAll(/ value="([^"]*)"/g), (match) => match[1]).join(' ');
      assert(words.includes(reason), 'visible error reason missing: ' + reason);
      assert(!text.includes('This partial page must stay hidden'));
      assert(!job.log.includes('authenticated tls='));
    } else {
      assert(job.log.includes('authenticated tls=1.3'), job.log);
      assert(text.includes('TITLE Both stages completed\n'));
    }
    console.log('PASS ' + name + ' at ' + elapsed.toFixed(1) + ' ms');
  }));
  backlog.process.kill();
}

async function wayland() {
  const requests = [];
  const held = new Map();
  const closed = new Set();
  const port = await listen(http.createServer((request, response) => {
    requests.push(request.url);
    if (request.url === '/active') {
      const lines = Array.from({ length: 120 }, (_, i) => '<p>Scrollable line ' + i + '</p>');
      page(response, 'Active viewport', lines.join(''));
    }
    else if (request.url === '/fresh') page(response, 'Replacement');
    else if (request.url === '/sheets') page(response, 'Pending stylesheet', '<link rel="stylesheet" href="/held.css">');
    else {
      held.set(request.url, response);
      response.once('close', () => closed.add(request.url));
    }
  }));
  const base = 'http://127.0.0.1:' + port;
  const display = 'navigation-' + process.pid;
  const runtime = resolve('.deps/runtime');
  const libs = resolve('.deps/root/usr/lib/x86_64-linux-gnu');
  const env = { ...process.env, WAYLAND_DISPLAY: display, XDG_RUNTIME_DIR: runtime,
    LD_LIBRARY_PATH: libs + ':' + join(libs, 'weston') };
  const compositor = launch('sh', ['tools/wayland-headless.sh', display], { env });
  await until(() => existsSync(join(runtime, display)), 'owned Weston socket');
  const script = join(run, 'events.live');
  const layout = join(run, 'wayland.layout');
  const current = () => existsSync(layout) ? readFileSync(layout, 'utf8') : '';
  writeFileSync(script, [
    '600 open ' + base + '/cancel',
    '1500 scroll 630',
    '2800 key 1',
    '3000 back',
    '3400 open ' + base + '/late',
    '4000 address ' + base + '/fresh',
    '4000 key 28',
    '4600 back',
    '5100 down 56',
    '5100 key 106',
    '5100 up 56',
    '5600 open ' + base + '/sheets',
    '6400 key 1',
  ].join('\n') + '\n');
  const job = launch('timeout', ['14s', 'sh', 'tools/wayland-run.sh', base + '/active',
    '--max-ms', '7000', '--live-script', script, '--layout', layout], { env });
  try {
    async function screenshot(name) {
      const dir = join(run, name);
      mkdirSync(dir);
      const shot = launch(resolve('.deps/root/usr/bin/weston-screenshooter'), [], { cwd: dir, env });
      await successful(shot);
      return join(dir, readdirSync(dir).find((file) => file.endsWith('.png')));
    }
    await until(() => held.has('/cancel') && current().includes('TITLE Active viewport\n'), 'initial live request');
    const before = await screenshot('before-scroll');
    await until(() => current().includes('SCROLL 630\n'), 'active viewport scrolled');
    // The layout dump is written before the next wl_surface.commit.
    await delay(150);
    const after = await screenshot('during-load');
    assert(!closed.has('/cancel'), 'viewport frames must precede Escape and peer completion');
    const compare = launch('python3', ['-c', `
from PIL import Image, ImageChops
import sys
first, second = [Image.open(name).convert("RGB") for name in sys.argv[1:]]
width, height = first.size
difference = ImageChops.difference(first, second)
assert difference.crop((0, 50, width, 52)).getbbox(), "loading bar did not move"
assert difference.crop((0, 52, width, height)).getbbox(), "active viewport did not repaint"
`, before, after]);
    await successful(compare);
    await until(() => closed.has('/cancel'), 'Escape closed the outstanding socket', 2800);
    assert(current().includes('TITLE Active viewport\n') && current().includes('SCROLL 630\n'));

    await until(() => held.has('/late') && current().includes('TITLE Replacement\n'), 'replacement commit');
    await until(() => closed.has('/late'), 'superseded socket closed');
    page(held.get('/late'), 'Stale result');
    assert(!current().includes('TITLE Stale result\n'));

    await until(() => held.has('/held.css'), 'stylesheet request following back/forward', 2500);
    await until(() => closed.has('/held.css'), 'Escape closed the nested stylesheet socket', 1800);
    await successful(job);
    assert(current().includes('TITLE Replacement\n'), current());
    assert.equal(requests.filter((url) => url === '/active').length, 2, 'cancel must leave history intact');
    assert.equal(requests.filter((url) => url === '/fresh').length, 2, 'forward must reach replacement');
    assert(!job.log.includes('NAV_ERROR') && !job.log.includes('Stale result'), job.log);
    assert.match(job.log, /presented ([1-9][0-9]+) frames/);
    console.log('PASS Weston animation, active viewport repaint, Escape, supersession, history and stylesheet cancellation');
  } finally {
    writeFileSync(join(run, 'wayland.log'), job.log);
    writeFileSync(join(run, 'compositor.log'), compositor.log);
  }
}

(async () => {
  try {
    await phases();
    if (process.argv.includes('--wayland')) await wayland();
  } finally {
    for (const job of children) job.process.kill();
    for (const socket of sockets) socket.destroy();
    for (const server of servers) server.close();
    await Promise.all(children.map((job) => job.done));
    console.log('Navigation evidence: ' + run);
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });
