import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { Account, validateAccount } from '../core/Core';
import { aliyunUrl } from '../core/Signing';

export class AliyunCredential { id: string = ''; secret: string = ''; }

export class NetClient {
  async query(account: Account, credential: string): Promise<string> {
    validateAccount(account);
    let url: string = account.endpoint;
    const headers: Record<string, string> = { Accept: 'application/json' };
    if (account.platform === 'dashscope') {
      const key: AliyunCredential = JSON.parse(credential) as AliyunCredential;
      if (!key.id || !key.secret) throw new Error('请配置阿里云 AccessKeyId 与 AccessKeySecret');
      url = aliyunUrl(key.id, key.secret, util.generateRandomUUID(), new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'));
    } else if (account.platform === 'mimo') headers['Cookie'] = credential;
    else headers['Authorization'] = 'Bearer ' + credential;
    if (account.platform === 'qiniu') {
      const today: string = new Date().toISOString().slice(0, 10);
      url += '?start_date=' + today.slice(0, 8) + '01&end_date=' + today;
    }
    const client: http.HttpRequest = http.createHttp();
    let timer: number = -1;
    try {
      const options: http.HttpRequestOptions = {
        method: account.method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: headers, expectDataType: http.HttpDataType.STRING,
        connectTimeout: 3000, readTimeout: 4000, usingCache: false,
        maxRedirects: 0, maxLimit: 1048576, remoteValidation: 'system'
      };
      if (account.method === 'POST') { options.extraData = '{}'; headers['Content-Type'] = 'application/json'; }
      const reply: http.HttpResponse = await Promise.race<http.HttpResponse>([
        client.request(url, options),
        new Promise<http.HttpResponse>((_, reject) => {
          timer = setTimeout(() => { client.destroy(); reject(new Error('查询超时，请检查网络后重试')); }, 7000);
        })
      ]);
      if (reply.responseCode >= 300 && reply.responseCode < 400) throw new Error('查询接口发生重定向，请使用最终官方查询地址');
      if (reply.responseCode === 401 || reply.responseCode === 403) throw new Error('凭证失效或缺少余额查询权限');
      if (reply.responseCode === 429) throw new Error('平台限流，请稍后重试');
      if (reply.responseCode !== 200) throw new Error('平台响应 HTTP ' + reply.responseCode);
      const text: string = reply.result as string;
      if (typeof text !== 'string' || text.length > 1048576) throw new Error('接口响应为空或过大');
      return text;
    } catch (error) {
      // 原始异常可能包含签名 URL，绝不显示或记录它。
      if (error instanceof Error && /^(查询超时|查询接口|凭证失效|平台限流|平台响应 HTTP|接口响应)/.test(error.message)) {
        throw new Error(error.message);
      }
      throw new Error('网络查询失败，请检查网络、地址和平台服务');
    } finally {
      if (timer >= 0) clearTimeout(timer);
      client.destroy();
    }
  }
}
