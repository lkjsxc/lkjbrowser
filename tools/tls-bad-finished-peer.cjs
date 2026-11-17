#!/usr/bin/env node
'use strict';
// Independent TLS 1.3 adversarial TEST PEER. Never executed by the browser.
// Uses Node/OpenSSL crypto solely to construct authenticated test records.
// All keys/certificates loaded here are public synthetic fixtures under tests/x509.
const net = require('node:net');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const [mode = 'good', portFile] = process.argv.slice(2);
if (!portFile || !['good', 'bad-finished', 'bad-signature', 'fragmented', 'key-update'].includes(mode)) {
  throw new Error('Usage: node tools/tls-bad-finished-peer.cjs MODE PORT_FILE.json');
}
const root = path.resolve(__dirname, '..');
const signingKey = crypto.createPrivateKey(fs.readFileSync(path.join(root, 'tests/x509/localhost.key')));
const pem = fs.readFileSync(path.join(root, 'tests/x509/localhost.pem'), 'ascii');
const certificate = Buffer.from(pem.replace(/-----[^-]+-----/g, '').replace(/\s/g, ''), 'base64');
const Z = Buffer.alloc(32);
const H = data => crypto.createHash('sha256').update(data).digest();
const MAC = (key, data) => crypto.createHmac('sha256', key).update(data).digest();
const U16 = n => Buffer.from([n >>> 8, n & 255]);
const U24 = n => Buffer.from([n >>> 16, (n >>> 8) & 255, n & 255]);
const cat = (...parts) => Buffer.concat(parts);
const handshake = (type, body) => cat(Buffer.from([type]), U24(body.length), body);
function expand(key, info, length) {
  let out = Buffer.alloc(0), previous = Buffer.alloc(0);
  for (let n = 1; out.length < length; n++) {
    previous = MAC(key, cat(previous, info, Buffer.from([n])));
    out = cat(out, previous);
  }
  return out.subarray(0, length);
}
function label(secret, name, context, length = 32) {
  const text = Buffer.from('tls13 ' + name);
  return expand(secret, cat(U16(length), Buffer.from([text.length]), text,
    Buffer.from([context.length]), context), length);
}
function epoch(secret) {
  return {secret, key: label(secret, 'key', Buffer.alloc(0), 16),
    iv: label(secret, 'iv', Buffer.alloc(0), 12), sequence: 0n};
}
function nonce(keys) {
  const n = Buffer.from(keys.iv), seq = Buffer.alloc(8);
  seq.writeBigUInt64BE(keys.sequence++);
  for (let i = 0; i < 8; i++) n[i + 4] ^= seq[i];
  return n;
}
function protect(keys, type, body) {
  const inner = cat(body, Buffer.from([type]));
  const header = cat(Buffer.from([23, 3, 3]), U16(inner.length + 16));
  const cipher = crypto.createCipheriv('aes-128-gcm', keys.key, nonce(keys));
  cipher.setAAD(header, {plaintextLength: inner.length});
  return cat(header, cipher.update(inner), cipher.final(), cipher.getAuthTag());
}
function unprotect(keys, record) {
  if (record.length < 22) throw new Error('short protected record');
  const decipher = crypto.createDecipheriv('aes-128-gcm', keys.key, nonce(keys));
  decipher.setAAD(record.subarray(0, 5), {plaintextLength: record.length - 21});
  decipher.setAuthTag(record.subarray(record.length - 16));
  const inner = cat(decipher.update(record.subarray(5, record.length - 16)), decipher.final());
  let end = inner.length;
  while (end && inner[end - 1] === 0) end--;
  if (!end) throw new Error('missing inner type');
  return {type: inner[end - 1], body: inner.subarray(0, end - 1)};
}
function clientHello(message) {
  if (message[0] !== 1) throw new Error('expected ClientHello');
  const b = message.subarray(4);
  let p = 34;
  const session = Buffer.from(b.subarray(p + 1, p + 1 + b[p])); p += 1 + b[p];
  const n = b.readUInt16BE(p); p += 2;
  const suites = b.subarray(p, p + n); p += n;
  let suiteOkay = false;
  for (let i = 0; i < suites.length; i += 2) if (suites.readUInt16BE(i) === 0x1301) suiteOkay = true;
  p += 1 + b[p];
  const end = p + 2 + b.readUInt16BE(p); p += 2;
  if (!suiteOkay || end !== b.length) throw new Error('unsupported ClientHello');
  let share, alpn = false, tls13 = false;
  while (p < end) {
    const type = b.readUInt16BE(p), size = b.readUInt16BE(p + 2); p += 4;
    const ext = b.subarray(p, p + size); p += size;
    if (p > end) throw new Error('truncated extension');
    if (type === 43) for (let q = 1; q + 1 < ext.length; q += 2) if (ext.readUInt16BE(q) === 0x0304) tls13 = true;
    if (type === 16) {
      for (let q = 2; q < ext.length;) {
        const size = ext[q++];
        if (ext.subarray(q, q + size).toString('ascii') === 'http/1.1') alpn = true;
        q += size;
      }
    }
    if (type === 51) {
      for (let q = 2; q + 4 <= ext.length;) {
        const group = ext.readUInt16BE(q), size = ext.readUInt16BE(q + 2); q += 4;
        if (group === 29 && size === 32) share = Buffer.from(ext.subarray(q, q + size));
        q += size;
      }
    }
  }
  if (!tls13 || !share) throw new Error('TLS 1.3 X25519 required');
  return {session, share, alpn};
}
const body = Buffer.from('<!doctype html><html><head><title>Authenticated test peer</title></head><body><h1>Authenticated test peer</h1><p>The TLS handshake and application record were verified.</p></body></html>');
const response = cat(Buffer.from('HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: ' + body.length +
  '\r\nConnection: close\r\n\r\n'), body);
const sockets = new Set();
const server = net.createServer(socket => {
  sockets.add(socket);
  let pending = Buffer.alloc(0), hsPending = Buffer.alloc(0), request = Buffer.alloc(0);
  let phase = 'hello', transcript = Buffer.alloc(0), clientHs, serverHs, clientApp, serverApp;
  socket.setTimeout(15000, () => socket.destroy());
  function emitFlight(message) {
    if (mode === 'fragmented') {
      // Message boundaries deliberately cross multiple independently protected records.
      for (let at = 0; at < message.length; at += 37) socket.write(protect(serverHs, 22, message.subarray(at, at + 37)));
    } else socket.write(protect(serverHs, 22, message));
  }
  function hello(message) {
    const ch = clientHello(message);
    const pair = crypto.generateKeyPairSync('x25519');
    const peer = crypto.createPublicKey({key: cat(Buffer.from('302a300506032b656e032100', 'hex'), ch.share),
      format: 'der', type: 'spki'});
    const shared = crypto.diffieHellman({privateKey: pair.privateKey, publicKey: peer});
    if (shared.equals(Z)) throw new Error('zero X25519 share');
    const publicKey = pair.publicKey.export({format: 'der', type: 'spki'}).subarray(-32);
    const exts = cat(Buffer.from('002b0002030400330024001d0020', 'hex'), publicKey);
    const sh = handshake(2, cat(Buffer.from([3, 3]), crypto.randomBytes(32),
      Buffer.from([ch.session.length]), ch.session, Buffer.from([0x13, 1, 0]), U16(exts.length), exts));
    transcript = cat(message, sh);
    const early = MAC(Z, Z), hs = MAC(label(early, 'derived', H(Buffer.alloc(0))), shared);
    const clientSecret = label(hs, 'c hs traffic', H(transcript));
    const serverSecret = label(hs, 's hs traffic', H(transcript));
    clientHs = epoch(clientSecret); serverHs = epoch(serverSecret);
    const alpn = ch.alpn ? Buffer.from('0010000b000908687474702f312e31', 'hex') : Buffer.alloc(0);
    const ee = handshake(8, cat(U16(alpn.length), alpn));
    const entry = cat(U24(certificate.length), certificate, Buffer.from([0, 0]));
    const cert = handshake(11, cat(Buffer.from([0]), U24(entry.length), entry));
    transcript = cat(transcript, ee, cert);
    const toSign = cat(Buffer.alloc(64, 0x20), Buffer.from('TLS 1.3, server CertificateVerify\0'), H(transcript));
    const signature = crypto.sign('sha256', toSign, signingKey);
    if (mode === 'bad-signature') signature[signature.length - 1] ^= 1;
    const cv = handshake(15, cat(Buffer.from([4, 3]), U16(signature.length), signature));
    transcript = cat(transcript, cv);
    const verify = MAC(label(serverSecret, 'finished', Buffer.alloc(0)), H(transcript));
    if (mode === 'bad-finished') verify[0] ^= 1;
    const finished = handshake(20, verify);
    transcript = cat(transcript, finished);
    const master = MAC(label(hs, 'derived', H(Buffer.alloc(0))), Z);
    clientApp = epoch(label(master, 'c ap traffic', H(transcript)));
    serverApp = epoch(label(master, 's ap traffic', H(transcript)));
    socket.write(cat(Buffer.from([22, 3, 3]), U16(sh.length), sh));
    emitFlight(cat(ee, cert, cv, finished));
    phase = 'finish';
  }
  function protectedRecord(record) {
    const keys = phase === 'finish' ? clientHs : clientApp;
    const plain = unprotect(keys, record);
    if (plain.type === 21) { socket.end(); return; }
    if (phase === 'finish') {
      if (plain.type !== 22) throw new Error('expected encrypted client Finished');
      hsPending = cat(hsPending, plain.body);
      if (hsPending.length < 4) return;
      const length = hsPending.readUIntBE(1, 3);
      if (hsPending.length < length + 4) return;
      if (hsPending[0] !== 20 || length !== 32 || hsPending.length !== 36) throw new Error('invalid client Finished');
      const expected = MAC(label(clientHs.secret, 'finished', Buffer.alloc(0)), H(transcript));
      if (!crypto.timingSafeEqual(expected, hsPending.subarray(4))) throw new Error('client Finished mismatch');
      hsPending = Buffer.alloc(0); phase = 'http'; return;
    }
    if (plain.type === 22) {
      if (plain.body.length === 5 && plain.body[0] === 24 && plain.body[4] <= 1) {
        clientApp = epoch(label(clientApp.secret, 'traffic upd', Buffer.alloc(0)));
        return;
      }
      throw new Error('unexpected post-handshake message');
    }
    if (plain.type !== 23) throw new Error('expected application data');
    request = cat(request, plain.body);
    if (request.length > 65536) throw new Error('oversized request');
    if (request.includes('\r\n\r\n')) {
      if (mode === 'key-update') {
        socket.write(protect(serverApp, 22, handshake(24, Buffer.from([1]))));
        serverApp = epoch(label(serverApp.secret, 'traffic upd', Buffer.alloc(0)));
      }
      socket.write(protect(serverApp, 23, response));
      socket.end(protect(serverApp, 21, Buffer.from([1, 0])));
      phase = 'closed';
    }
  }
  socket.on('data', bytes => {
    try {
      pending = cat(pending, bytes);
      if (pending.length > 262144) throw new Error('input limit');
      while (pending.length >= 5) {
        const n = pending.readUInt16BE(3) + 5;
        if (n > 16645) throw new Error('record limit');
        if (pending.length < n) break;
        const record = pending.subarray(0, n); pending = pending.subarray(n);
        if (record[0] === 20 && n === 6 && record[5] === 1) continue;
        if (phase === 'hello') {
          if (record[0] !== 22) throw new Error('expected initial handshake record');
          hsPending = cat(hsPending, record.subarray(5));
          if (hsPending.length < 4) continue;
          const length = hsPending.readUIntBE(1, 3);
          if (hsPending.length < length + 4) continue;
          if (hsPending.length !== length + 4) throw new Error('extra initial handshake');
          hello(hsPending); hsPending = Buffer.alloc(0);
        } else if (phase !== 'closed') {
          if (record[0] !== 23) throw new Error('expected protected record');
          protectedRecord(record);
        }
      }
    } catch (error) {
      // Diagnostics contain only a stage/error description, never key or transcript bytes.
      process.stderr.write('test peer: ' + error.message + '\n'); socket.destroy();
    }
  });
  socket.on('error', () => {});
  socket.on('close', () => sockets.delete(socket));
});
function stop() { for (const socket of sockets) socket.destroy(); server.close(() => process.exit(0)); }
process.on('SIGINT', stop); process.on('SIGTERM', stop);
server.listen(0, '127.0.0.1', () => {
  fs.writeFileSync(portFile, JSON.stringify({port: server.address().port, pid: process.pid, mode}) + '\n');
});
