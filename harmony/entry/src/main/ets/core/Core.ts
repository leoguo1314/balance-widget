/** 平台无关业务逻辑。Node 测试直接执行本文件；不依赖模拟的余额数据。 */
export class Account {
  id: string = '';
  platform: string = 'deepseek';
  label: string = '';
  group: string = '';
  currency: string = 'CNY';
  endpoint: string = '';
  path: string = '';
  method: string = 'GET';
  allowHttp: boolean = false;
  threshold: number = 10;
  enabled: boolean = true;
  includeInTotal: boolean = true;
  secretRef: string = '';
  secretParts: number = 0;
  revision: number = 0;
}

export class Preset {
  id: string;
  name: string;
  url: string;
  currency: string;
  path: string;
  note: string;
  constructor(id: string, name: string, url: string, currency: string,
    path: string = '', note: string = '') {
    this.id = id; this.name = name; this.url = url;
    this.currency = currency; this.path = path; this.note = note;
  }
}

export const PRESETS: Preset[] = [
  new Preset('deepseek', 'DeepSeek', 'https://api.deepseek.com/user/balance', 'CNY'),
  new Preset('siliconflow', '硅基流动', 'https://api.siliconflow.cn/v1/user/info', 'CNY'),
  new Preset('moonshot', 'Moonshot', 'https://api.moonshot.cn/v1/users/me/balance', 'CNY'),
  new Preset('openrouter', 'OpenRouter', 'https://openrouter.ai/api/v1/credits', 'USD'),
  new Preset('novita', 'Novita AI', 'https://api.novita.ai/v3/user/balance', 'USD'),
  new Preset('fireworks', 'Fireworks AI', 'https://api.fireworks.ai/v1/accounts', 'USD'),
  new Preset('zhipu', '智谱 AI', 'https://open.bigmodel.cn/api/paas/v4/user/balance', 'CNY', '', '沿用上游接口，需真实 Key 验证'),
  new Preset('dashscope', '阿里云百炼', 'https://business.aliyuncs.com/', 'CNY', '', '填写 AccessKeyId 和 AccessKeySecret；查询的是阿里云账户余额'),
  new Preset('compshare', '优云智算', 'https://api.compshare.cn/v1/user/balance', 'CNY'),
  new Preset('volc', '火山方舟', 'https://ark.cn-beijing.volces.com/api/v3/user/balance', 'CNY', '', '上游标记为未全量验证'),
  new Preset('spark', '讯飞星火', 'https://spark-api-open.xf-yun.com/v1/user/balance', 'CNY', '', '上游标记为未全量验证'),
  new Preset('internlm', '书生 InternLM', 'https://internlm.intern-ai.org.cn/api/v1/user/balance', 'CNY', '', '上游标记为未全量验证'),
  new Preset('stepfun', '阶跃星辰', 'https://api.stepfun.com/v1/accounts', 'CNY', '', '上游标记为未全量验证'),
  new Preset('mimo', '小米 MiMo', 'https://platform.xiaomimimo.com/api/v1/balance', 'CNY', '', '保存后进入小米登录页验证会话'),
  new Preset('qiniu', '七牛云 AI', 'https://api.qnaigc.com/v3/stat/usage/apikey/cost-detail', 'CNY', '', '后付费消费，不计入总余额'),
  new Preset('modelscope', '魔搭 ModelScope', '', 'CNY', '', '免费平台，无余额接口'),
  new Preset('workbuddy', 'WorkBuddy 网关', '', 'POINT', '', '填写局域网网关地址，使用 POST /panel/api/balance_all'),
  new Preset('custom', '自定义平台', '', 'CNY', '', '需要平台提供独立余额接口；聊天协议兼容不能代替余额接口')
];

export function presetFor(id: string): Preset {
  const match: Preset | undefined = PRESETS.find((p: Preset) => p.id === id);
  if (!match) throw new Error('未知平台');
  return match;
}

export function newAccount(id: string, platform: string): Account {
  const p: Preset = presetFor(platform);
  const a: Account = new Account();
  a.id = id; a.platform = p.id; a.label = p.name;
  a.currency = p.currency; a.endpoint = p.url; a.path = p.path;
  a.includeInTotal = ['qiniu', 'modelscope', 'workbuddy'].indexOf(platform) < 0;
  a.method = platform === 'workbuddy' ? 'POST' : 'GET';
  return a;
}

export function validateAccount(a: Account): void {
  const p: Preset = presetFor(a.platform);
  if (!a.id || !a.label.trim()) throw new Error('请输入名称');
  if (a.label.length > 80 || a.group.length > 80) throw new Error('名称或账户组过长');
  if (!Number.isFinite(a.threshold) || a.threshold < 0) throw new Error('预警阈值应为非负数');
  if (['CNY', 'USD', 'POINT'].indexOf(a.currency) < 0) throw new Error('不支持该币种');
  if (['GET', 'POST'].indexOf(a.method) < 0) throw new Error('不支持该请求方式');
  if (a.platform !== 'custom' && a.method !== (a.platform === 'workbuddy' ? 'POST' : 'GET')) {
    throw new Error('内置平台的请求方式不可替换');
  }
  if (a.platform !== 'custom' && a.platform !== 'deepseek' && a.currency !== p.currency) {
    throw new Error('该平台使用固定币种');
  }
  if (a.platform === 'modelscope') return;
  const endpoint: string = a.endpoint.trim();
  const safeAddress: string = '(?:[A-Za-z0-9.-]+|\\[[0-9A-Fa-f:]+\\])(?::[0-9]{1,5})?(?:/[^\\s#\\\\]*)?';
  if (!new RegExp('^https://' + safeAddress + '$').test(endpoint) &&
    !(a.allowHttp && new RegExp('^http://' + safeAddress + '$').test(endpoint))) {
    throw new Error('请输入 HTTPS 查询地址；局域网 HTTP 需要明确开启允许选项');
  }
  if (/[?&](?:api[_-]?key|token|accesskeysecret|signature)=/i.test(endpoint)) {
    throw new Error('密钥请填在凭证栏，不要放进查询地址');
  }
  // 内置适配器的鉴权不得被误发送到修改后的域名。
  if (a.platform !== 'custom' && a.platform !== 'workbuddy' && a.endpoint !== p.url) {
    throw new Error('内置平台地址不可替换；第三方服务请使用自定义平台');
  }
  if (a.platform === 'workbuddy' && !/\/panel\/api\/balance_all\/?$/.test(endpoint)) {
    throw new Error('网关查询地址应以 /panel/api/balance_all 结尾');
  }
}

export class Balance {
  accountId: string = '';
  value: number = 0;
  currency: string = 'CNY';
  ok: boolean = false;
  hasValue: boolean = false;
  stale: boolean = false;
  updatedAt: number = 0;
  error: string = '';
  revision: number = 0;
}

export function numeric(value: Object | undefined): number | undefined {
  if (typeof value === 'number') return Number.isFinite(value) ? value : undefined;
  if (typeof value !== 'string' || !/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(value.trim())) return undefined;
  const n: number = Number(value);
  return Number.isFinite(n) ? n : undefined;
}

export function valueAt(root: Object, path: string): Object | undefined {
  const parts: string[] = path.replace(/\[(\d+)\]/g, '.$1').split('.').filter((s: string) => s.length > 0);
  let current: Object | undefined = root;
  for (const part of parts) {
    if (current === null || current === undefined || typeof current !== 'object') return undefined;
    if (Array.isArray(current)) {
      if (!/^\d+$/.test(part)) return undefined;
      current = (current as Object[])[Number(part)];
    } else {
      if (['__proto__', 'constructor', 'prototype'].indexOf(part) >= 0) return undefined;
      current = (current as Record<string, Object>)[part];
    }
  }
  return current;
}

function firstNumber(root: Object, paths: string[]): number | undefined {
  for (const path of paths) {
    const n: number | undefined = numeric(valueAt(root, path));
    if (n !== undefined) return n;
  }
  return undefined;
}

const GENERIC_PATHS: string[] = ['data.totalBalance', 'data.total_balance', 'data.availableBalance',
  'data.available_balance', 'data.balance', 'available_balance', 'availableBalance', 'totalBalance',
  'total_balance', 'balance', 'data.balance_amount', 'data.credit', 'credit', 'remaining'];

export function parseBalance(a: Account, body: string, now: number): Balance {
  let root: Object;
  try { root = JSON.parse(body) as Object; } catch (_) { throw new Error('接口没有返回有效 JSON'); }
  if (root === null || typeof root !== 'object') throw new Error('接口没有返回 JSON 对象');
  if (valueAt(root, 'success') === false || valueAt(root, 'Success') === false ||
    valueAt(root, 'status') === false || valueAt(root, 'error')) {
    throw new Error('平台返回业务错误，请检查凭证及账户权限');
  }
  let n: number | undefined;
  let currency: string = a.currency;
  if (a.platform === 'deepseek') {
    if (valueAt(root, 'is_available') === false) throw new Error('DeepSeek 账户不可用');
    const list: Object | undefined = valueAt(root, 'balance_infos');
    if (Array.isArray(list)) {
      const info: Object | undefined = (list as Object[]).find((item: Object) => valueAt(item, 'currency') === a.currency);
      if (info) n = firstNumber(info, ['total_balance']);
    }
  } else if (a.platform === 'openrouter') {
    const credits: number | undefined = firstNumber(root, ['data.total_credits']);
    const usage: number | undefined = firstNumber(root, ['data.total_usage']);
    if (credits !== undefined && usage !== undefined) n = credits - usage;
  } else if (a.platform === 'dashscope') {
    n = firstNumber(root, ['Data.AvailableAmount', 'AvailableAmount']);
    const unit: Object | undefined = valueAt(root, 'Data.Currency');
    if (typeof unit === 'string') currency = unit;
  } else if (a.platform === 'workbuddy') {
    const list: Object | undefined = valueAt(root, 'accounts');
    if (Array.isArray(list)) {
      const credits: number[] = [];
      (list as Object[]).forEach((item: Object) => {
        const value: number | undefined = numeric(valueAt(item, 'credits'));
        if (value === undefined) throw new Error('网关返回的账户积分不完整');
        credits.push(value);
      });
      n = credits.reduce((sum: number, value: number) => sum + value, 0);
    }
  } else if (a.platform === 'fireworks') {
    const list: Object | undefined = valueAt(root, 'accounts') || valueAt(root, 'data');
    if (Array.isArray(list)) {
      const balances: number[] = [];
      (list as Object[]).forEach((item: Object) => {
        const value: number | undefined = firstNumber(item, ['balance', 'creditBalance', 'credit_balance']);
        if (value !== undefined) balances.push(value);
      });
      if (balances.length > 0) n = Math.max(...balances);
    } else n = firstNumber(root, ['balance', 'creditBalance', 'credit_balance']);
  } else if (a.platform === 'qiniu') {
    n = firstNumber(root, ['data.total_fee', 'data.totalFee', 'total_fee', 'totalFee']);
  } else if (a.platform === 'siliconflow') {
    n = firstNumber(root, ['data.totalBalance', 'data.total_balance', 'data.balance', 'totalBalance', 'total_balance', 'balance']);
  } else if (a.platform === 'moonshot' || a.platform === 'novita') {
    n = firstNumber(root, ['data.available_balance', 'data.availableBalance', 'data.balance', 'available_balance', 'availableBalance', 'balance']);
  } else if (a.platform === 'mimo') {
    n = firstNumber(root, ['data.balance', 'data.availableBalance', 'data.available_balance', 'balance', 'availableBalance', 'available_balance', 'data.cashBalance', 'cashBalance']);
  } else if (a.path.trim()) n = numeric(valueAt(root, a.path.trim()));
  else n = firstNumber(root, GENERIC_PATHS);
  if (n === undefined) throw new Error('未识别余额字段，请检查查询地址或填写 JSON 取值路径');
  if (['CNY', 'USD', 'POINT'].indexOf(currency) < 0) throw new Error('返回币种暂不支持');
  const result: Balance = new Balance();
  result.accountId = a.id; result.value = n; result.currency = currency;
  result.revision = a.revision;
  result.ok = true; result.hasValue = true; result.updatedAt = now;
  return result;
}

export function failedBalance(a: Account, previous: Balance | undefined, message: string): Balance {
  const result: Balance = new Balance();
  result.accountId = a.id; result.currency = a.currency; result.error = message;
  result.revision = a.revision;
  if (previous && previous.hasValue && previous.revision === a.revision) {
    result.value = previous.value; result.currency = previous.currency;
    result.updatedAt = previous.updatedAt; result.hasValue = true; result.stale = true;
  }
  return result;
}

export function mergeBalances(current: Balance[], incoming: Balance[]): Balance[] {
  const merged: Map<string, Balance> = new Map();
  current.forEach((b: Balance) => merged.set(b.accountId, b));
  incoming.forEach((b: Balance) => merged.set(b.accountId, b));
  return Array.from(merged.values());
}

export class Summary {
  cny: number = 0;
  values: number = 0;
  cached: number = 0;
  missing: number = 0;
}

export function summarize(accounts: Account[], balances: Balance[], usdCny: number): Summary {
  if (!Number.isFinite(usdCny) || usdCny <= 0) throw new Error('美元折算率必须大于零');
  const summary: Summary = new Summary();
  const groups: Map<string, number> = new Map();
  accounts.filter((a: Account) => a.enabled && a.includeInTotal && a.currency !== 'POINT' &&
    ['qiniu', 'modelscope', 'workbuddy'].indexOf(a.platform) < 0).forEach((a: Account) => {
    const b: Balance | undefined = balances.find((item: Balance) => item.accountId === a.id && item.revision === a.revision);
    if (!b || !b.hasValue) { summary.missing++; return; }
    if (b.currency === 'POINT') return;
    if (b.stale) summary.cached++;
    const key: string = a.platform + ':' + (a.group.trim() ? 'group:' + a.group.trim() : 'account:' + a.id);
    const cny: number = b.value * (b.currency === 'USD' ? usdCny : 1);
    const previous: number | undefined = groups.get(key);
    groups.set(key, previous === undefined ? cny : Math.max(previous, cny));
  });
  groups.forEach((value: number) => { summary.cny += value; summary.values++; });
  return summary;
}

export class Snapshot {
  accountId: string = '';
  value: number = 0;
  currency: string = 'CNY';
  timestamp: number = 0;
  revision: number = 0;
}

export function sample(previous: Snapshot | undefined, b: Balance): Snapshot | undefined {
  if (!b.ok || b.stale || !b.hasValue) return undefined;
  if (previous && previous.accountId === b.accountId && previous.currency === b.currency && previous.revision === b.revision) {
    const gap: number = b.updatedAt - previous.timestamp;
    if (gap < 5 * 60000) return undefined;
    const epsilon: number = b.currency === 'POINT' ? 0.5 : 0.005;
    if (Math.abs(previous.value - b.value) < epsilon && gap < 6 * 3600000) return undefined;
  }
  const point: Snapshot = new Snapshot();
  point.accountId = b.accountId; point.value = b.value;
  point.currency = b.currency; point.timestamp = b.updatedAt;
  point.revision = b.revision;
  return point;
}

export class Usage {
  consumed: number = 0;
  increases: number = 0;
  points: number = 0;
}

/** 增长只标记为余额增加；无法从两个快照辨别充值、退款及区间内的混合消费。 */
export function usageOf(history: Snapshot[], id: string, from: number): Usage {
  const rows: Snapshot[] = history.filter((p: Snapshot) => p.accountId === id)
    .slice().sort((a: Snapshot, b: Snapshot) => a.timestamp - b.timestamp);
  const out: Usage = new Usage();
  for (let i: number = 0; i < rows.length; i++) {
    if (rows[i].timestamp < from) continue;
    out.points++;
    if (i === 0 || rows[i - 1].currency !== rows[i].currency) continue;
    const delta: number = rows[i].value - rows[i - 1].value;
    if (delta > 0) out.increases += delta; else out.consumed -= delta;
  }
  return out;
}

export function amount(value: number, currency: string): string {
  if (!Number.isFinite(value)) return '—';
  return (currency === 'USD' ? '$' : currency === 'CNY' ? '¥' : '') + value.toFixed(currency === 'POINT' ? 0 : 2)
    + (currency === 'POINT' ? ' 积分' : '');
}

export class CardData {
  total: string = '¥0.00';
  status: string = '打开应用添加平台';
  page: string = '1/1';
  name1: string = '暂无平台'; value1: string = '—';
  name2: string = ''; value2: string = '';
  name3: string = ''; value3: string = '';
  name4: string = ''; value4: string = '';
}

export function cardData(accounts: Account[], balances: Balance[], usdCny: number, page: number): CardData {
  const active: Account[] = accounts.filter((a: Account) => a.enabled);
  const pages: number = Math.max(1, Math.ceil(active.length / 4));
  const index: number = ((page % pages) + pages) % pages;
  const selected: Account[] = active.slice(index * 4, index * 4 + 4);
  const summary: Summary = summarize(accounts, balances, usdCny);
  const data: CardData = new CardData();
  data.total = summary.values > 0 || active.length === 0 ? amount(summary.cny, 'CNY') : '—';
  data.page = (index + 1) + '/' + pages;
  data.status = active.length === 0 ? '打开应用添加平台' : summary.cached + ' 项缓存 · ' + summary.missing + ' 项待查询';
  let oldest: number = 0;
  const names: string[] = []; const values: string[] = [];
  selected.forEach((a: Account) => {
    const b: Balance | undefined = balances.find((item: Balance) => item.accountId === a.id && item.revision === a.revision);
    if (b && b.hasValue && b.updatedAt > 0) oldest = oldest === 0 ? b.updatedAt : Math.min(oldest, b.updatedAt);
    names.push(a.label);
    values.push(a.platform === 'modelscope' ? '免费服务' :
      b && b.hasValue ? amount(b.value, b.currency) + (b.stale ? ' · 缓存' : '') : '待查询');
  });
  if (oldest > 0) data.status = '更新 ' + new Date(oldest).toLocaleTimeString() + ' · ' + data.status;
  if (selected.length > 0) { data.name1 = names[0]; data.value1 = values[0]; }
  data.name2 = names[1] || ''; data.value2 = values[1] || '';
  data.name3 = names[2] || ''; data.value3 = values[2] || '';
  data.name4 = names[3] || ''; data.value4 = values[3] || '';
  return data;
}
