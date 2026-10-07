/** 阿里云 RPC V1 签名。纯函数，测试与 Node 原生 HMAC 交叉核验。 */
export function utf8(text: string): number[] {
  const bytes: number[] = [];
  for (let i: number = 0; i < text.length; i++) {
    let c: number = text.charCodeAt(i);
    if (c >= 0xD800 && c <= 0xDBFF) {
      const low: number = i + 1 < text.length ? text.charCodeAt(i + 1) : 0;
      if (low >= 0xDC00 && low <= 0xDFFF) { c = 0x10000 + ((c - 0xD800) << 10) + low - 0xDC00; i++; }
      else c = 0xFFFD;
    } else if (c >= 0xDC00 && c <= 0xDFFF) c = 0xFFFD;
    if (c < 0x80) bytes.push(c);
    else if (c < 0x800) bytes.push(0xC0 | (c >>> 6), 0x80 | (c & 63));
    else if (c < 0x10000) bytes.push(0xE0 | (c >>> 12), 0x80 | ((c >>> 6) & 63), 0x80 | (c & 63));
    else bytes.push(0xF0 | (c >>> 18), 0x80 | ((c >>> 12) & 63), 0x80 | ((c >>> 6) & 63), 0x80 | (c & 63));
  }
  return bytes;
}

function rotate(value: number, count: number): number { return (value << count) | (value >>> (32 - count)); }

export function sha1(input: number[]): number[] {
  const data: number[] = input.slice();
  const bits: number = data.length * 8;
  data.push(128);
  while (data.length % 64 !== 56) data.push(0);
  data.push(0, 0, 0, 0, (bits >>> 24) & 255, (bits >>> 16) & 255, (bits >>> 8) & 255, bits & 255);
  let h0: number = 0x67452301; let h1: number = 0xEFCDAB89; let h2: number = 0x98BADCFE;
  let h3: number = 0x10325476; let h4: number = 0xC3D2E1F0;
  for (let offset: number = 0; offset < data.length; offset += 64) {
    const w: number[] = [];
    for (let i: number = 0; i < 16; i++) {
      const j: number = offset + i * 4;
      w[i] = (data[j] << 24) | (data[j + 1] << 16) | (data[j + 2] << 8) | data[j + 3];
    }
    for (let i: number = 16; i < 80; i++) w[i] = rotate(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    let a: number = h0; let b: number = h1; let c: number = h2; let d: number = h3; let e: number = h4;
    for (let i: number = 0; i < 80; i++) {
      let f: number; let k: number;
      if (i < 20) { f = (b & c) | (~b & d); k = 0x5A827999; }
      else if (i < 40) { f = b ^ c ^ d; k = 0x6ED9EBA1; }
      else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC; }
      else { f = b ^ c ^ d; k = 0xCA62C1D6; }
      const temp: number = (rotate(a, 5) + f + e + k + w[i]) | 0;
      e = d; d = c; c = rotate(b, 30); b = a; a = temp;
    }
    h0 = (h0 + a) | 0; h1 = (h1 + b) | 0; h2 = (h2 + c) | 0; h3 = (h3 + d) | 0; h4 = (h4 + e) | 0;
  }
  const out: number[] = [];
  [h0, h1, h2, h3, h4].forEach((h: number) => out.push((h >>> 24) & 255, (h >>> 16) & 255, (h >>> 8) & 255, h & 255));
  return out;
}

export function hmacSha1(key: string, message: string): number[] {
  let bytes: number[] = utf8(key);
  if (bytes.length > 64) bytes = sha1(bytes);
  const inner: number[] = []; const outer: number[] = [];
  for (let i: number = 0; i < 64; i++) { inner.push((bytes[i] || 0) ^ 0x36); outer.push((bytes[i] || 0) ^ 0x5C); }
  return sha1(outer.concat(sha1(inner.concat(utf8(message)))));
}

export function base64(bytes: number[]): string {
  const table: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let output: string = '';
  for (let i: number = 0; i < bytes.length; i += 3) {
    const word: number = (bytes[i] << 16) | ((bytes[i + 1] || 0) << 8) | (bytes[i + 2] || 0);
    output += table[(word >>> 18) & 63] + table[(word >>> 12) & 63]
      + (i + 1 < bytes.length ? table[(word >>> 6) & 63] : '=')
      + (i + 2 < bytes.length ? table[word & 63] : '=');
  }
  return output;
}

export function rpcEncode(value: string): string {
  return encodeURIComponent(value).replace(/[!'()*]/g, (c: string) => '%' + c.charCodeAt(0).toString(16).toUpperCase());
}

export function aliyunUrl(id: string, secret: string, nonce: string, timestamp: string): string {
  const params: Record<string, string> = {
    AccessKeyId: id, Action: 'QueryAccountBalance', Format: 'JSON', SignatureMethod: 'HMAC-SHA1',
    SignatureNonce: nonce, SignatureVersion: '1.0', Timestamp: timestamp, Version: '2017-12-14'
  };
  const query: string = Object.keys(params).sort().map((key: string) => rpcEncode(key) + '=' + rpcEncode(params[key])).join('&');
  const sign: string = base64(hmacSha1(secret + '&', 'GET&%2F&' + rpcEncode(query)));
  return 'https://business.aliyuncs.com/?' + query + '&Signature=' + rpcEncode(sign);
}
