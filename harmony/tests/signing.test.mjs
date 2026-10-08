import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, createHmac } from 'node:crypto';
import { utf8, sha1, hmacSha1, base64, rpcEncode, aliyunUrl } from '../entry/src/main/ets/core/Signing.ts';

test('UTF-8 与 Node 编码一致，包括中文、emoji 和孤立代理项', () => {
  for (const s of ['', 'abc', '鸿蒙7余额', '😀🔐', '\uD800', '\uDC00', 'a\uD800b']) {
    assert.deepEqual(utf8(s), Array.from(Buffer.from(s, 'utf8')));
  }
});

test('SHA-1 与 Node 交叉验证：空值、块边界与多块输入', () => {
  for (const s of ['', 'abc', 'a'.repeat(55), 'a'.repeat(56), 'a'.repeat(64), '鸿蒙'.repeat(100)]) {
    assert.equal(Buffer.from(sha1(utf8(s))).toString('hex'), createHash('sha1').update(s).digest('hex'));
  }
});

test('HMAC-SHA1 对短密钥、长密钥、Unicode 和空输入与 Node 一致', () => {
  for (const [key, message] of [['key', 'hello'], ['a'.repeat(80), 'payload'], ['密钥😀', 'GET&%2F&查询'], ['', '']]) {
    assert.equal(base64(hmacSha1(key, message)), createHmac('sha1', key).update(message).digest('base64'));
  }
});

test('Base64 各填充边界与 Node 一致', () => {
  for (let count = 0; count < 80; count++) {
    const bytes = Array.from({ length: count }, (_, i) => (i * 67) % 256);
    assert.equal(base64(bytes), Buffer.from(bytes).toString('base64'));
  }
});

test('RPC 编码使用严格 RFC3986 编码', () => {
  assert.equal(rpcEncode(" !'()*~+"), '%20%21%27%28%29%2A~%2B');
});

test('阿里云请求排序、双层编码、签名和凭证保密符合 RPC V1', () => {
  const id = 'synthetic-id+test'; const secret = 'synthetic-secret-for-test';
  const nonce = 'nonce-test'; const timestamp = '2026-10-07T12:00:00Z';
  const url = new URL(aliyunUrl(id, secret, nonce, timestamp));
  const signature = url.searchParams.get('Signature'); url.searchParams.delete('Signature');
  const strictEncode = s => encodeURIComponent(s).replace(/[!'()*]/g, c => '%' + c.charCodeAt(0).toString(16).toUpperCase());
  const entries = Array.from(url.searchParams.entries()).sort(([a], [b]) => a.localeCompare(b));
  const canonical = entries.map(([k, v]) => strictEncode(k) + '=' + strictEncode(v)).join('&');
  const expected = createHmac('sha1', secret + '&').update('GET&%2F&' + strictEncode(canonical)).digest('base64');
  assert.equal(signature, expected);
  assert.equal(url.origin, 'https://business.aliyuncs.com');
  assert.equal(url.searchParams.get('Action'), 'QueryAccountBalance');
  assert.equal(url.searchParams.get('Version'), '2017-12-14');
  assert.ok(!aliyunUrl(id, secret, nonce, timestamp).includes(secret));
});
