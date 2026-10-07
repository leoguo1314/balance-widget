import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';

export class SecretReference {
  name: string = '';
  parts: number = 0;
}

/** 只有 SECRET 属性包含凭证；普通偏好、卡片、导出与日志均不包含凭证。 */
export class Vault {
  private bytes(text: string): Uint8Array { return new util.TextEncoder().encodeInto(text); }

  async write(secret: string): Promise<SecretReference> {
    const data: Uint8Array = this.bytes(secret);
    if (data.length === 0 || data.length > 28800) throw new Error('凭证长度应为 1–28800 字节');
    const ref: SecretReference = new SecretReference();
    ref.name = 'balance-' + util.generateRandomUUID();
    ref.parts = Math.ceil(data.length / 900);
    let written: number = 0;
    try {
      for (let i: number = 0; i < ref.parts; i++) {
        const attrs: asset.AssetMap = new Map();
        attrs.set(asset.Tag.ALIAS, this.bytes(ref.name + '-' + i));
        attrs.set(asset.Tag.SECRET, data.slice(i * 900, (i + 1) * 900));
        attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
        attrs.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
        await asset.add(attrs);
        written++;
      }
      return ref;
    } catch (_) {
      await this.remove(ref.name, written);
      throw new Error('安全凭证保存失败，请解锁手机后重试');
    }
  }

  async read(name: string, parts: number): Promise<string> {
    if (!name || parts < 1 || parts > 32) throw new Error('尚未配置凭证');
    const chunks: Uint8Array[] = []; let total: number = 0;
    for (let i: number = 0; i < parts; i++) {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, this.bytes(name + '-' + i));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const found: asset.AssetMap[] = await asset.query(query);
      if (found.length !== 1) throw new Error('安全凭证不可用，请重新保存 Key');
      const chunk: Uint8Array = found[0].get(asset.Tag.SECRET) as Uint8Array;
      chunks.push(chunk); total += chunk.length;
    }
    const data: Uint8Array = new Uint8Array(total); let offset: number = 0;
    chunks.forEach((chunk: Uint8Array) => { data.set(chunk, offset); offset += chunk.length; });
    return util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeWithStream(data);
  }

  async remove(name: string, parts: number): Promise<void> {
    if (!name) return;
    for (let i: number = 0; i < Math.min(parts, 32); i++) {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, this.bytes(name + '-' + i));
      try { await asset.remove(query); } catch (_) { /* 无日志暴露凭证；孤立旧引用不影响新凭证。 */ }
    }
  }
}
