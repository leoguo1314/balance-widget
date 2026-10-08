import test from 'node:test';
import assert from 'node:assert/strict';
import {
  PRESETS, newAccount, validateAccount, numeric, valueAt, parseBalance, failedBalance,
  summarize, sample, usageOf, amount, cardData, mergeBalances
} from '../entry/src/main/ets/core/Core.ts';

const minute = 60_000;
const account = (id = 'one', platform = 'deepseek') => newAccount(id, platform);
function balance(a, value, now = 1_000_000, currency = a.currency) {
  return { accountId: a.id, value, currency, ok: true, hasValue: true, stale: false, updatedAt: now, error: '', revision: a.revision };
}
const snapshot = (value, timestamp, id = 'one', currency = 'CNY') => ({ accountId: id, value, timestamp, currency, revision: 0 });
const parse = (platform, object, currency) => {
  const a = account('one', platform);
  if (currency) a.currency = currency;
  return parseBalance(a, JSON.stringify(object), 1_000_000);
};

test('18 个预设有独立 ID；内置地址均使用 HTTPS', () => {
  assert.equal(PRESETS.length, 18);
  assert.equal(new Set(PRESETS.map(p => p.id)).size, PRESETS.length);
  for (const p of PRESETS) {
    if (p.url) assert.match(p.url, /^https:\/\//);
    if (!['custom', 'workbuddy'].includes(p.id)) validateAccount(account(p.id, p.id));
  }
});

test('数值解析接受零、负余额、小数和科学计数法', () => {
  assert.equal(numeric(0), 0);
  assert.equal(numeric(' -2.5 '), -2.5);
  assert.equal(numeric('1.25e2'), 125);
});

test('数值解析拒绝空值、布尔值、非有限值和非十进制内容', () => {
  for (const v of [null, undefined, false, true, '', ' ', '0xff', 'Infinity', NaN, Infinity, 'abc', '1,234']) {
    assert.equal(numeric(v), undefined, String(v));
  }
});

test('JSON 取值路径支持数组并阻止原型访问', () => {
  assert.equal(valueAt({ data: { accounts: [{ balance: '8.5' }] } }, 'data.accounts[0].balance'), '8.5');
  assert.equal(valueAt({}, '__proto__.toString'), undefined);
  assert.equal(valueAt({}, 'constructor'), undefined);
  assert.equal(valueAt({ data: null }, 'data.balance'), undefined);
});

test('DeepSeek 根据币种读取总余额，不相加多币种余额', () => {
  const response = { is_available: true, balance_infos: [
    { currency: 'USD', total_balance: '4' }, { currency: 'CNY', total_balance: '28.50' }
  ] };
  assert.equal(parse('deepseek', response).value, 28.5);
  assert.equal(parse('deepseek', response, 'USD').value, 4);
});

test('DeepSeek 缺少币种或账户不可用时返回错误', () => {
  assert.throws(() => parse('deepseek', { is_available: false, balance_infos: [] }), /不可用/);
  assert.throws(() => parse('deepseek', { is_available: true, balance_infos: [{ currency: 'EUR', total_balance: '10' }] }), /余额字段/);
});

test('硅基流动选择 totalBalance 而非其中的现金余额', () => {
  assert.equal(parse('siliconflow', { data: { totalBalance: '19', balance: '2' } }).value, 19);
});

test('Moonshot 和 Novita 优先使用可用余额', () => {
  for (const platform of ['moonshot', 'novita']) {
    assert.equal(parse(platform, { data: { available_balance: '7.2', totalBalance: '900', balance: '2' } }).value, 7.2);
  }
});

test('OpenRouter 用累计充值减已用，并保留欠费负值', () => {
  assert.equal(parse('openrouter', { data: { total_credits: 100, total_usage: 22.5 } }).value, 77.5);
  assert.equal(parse('openrouter', { data: { total_credits: '1', total_usage: '2.5' } }).value, -1.5);
  assert.throws(() => parse('openrouter', { data: { total_credits: 100 } }), /余额字段/);
});

test('阿里云解析 BSS 账户余额及响应币种', () => {
  const b = parse('dashscope', { Success: true, Data: { AvailableAmount: '12.34', Currency: 'USD' } });
  assert.equal(b.value, 12.34);
  assert.equal(b.currency, 'USD');
  assert.throws(() => parse('dashscope', { Success: false, Data: { AvailableAmount: '0' } }), /业务错误/);
});

test('Fireworks 沿用上游取可识别账户余额最大值', () => {
  assert.equal(parse('fireworks', { accounts: [{ balance: '4' }, { creditBalance: '8' }, {}] }).value, 8);
  assert.throws(() => parse('fireworks', { accounts: [{}] }), /余额字段/);
});

test('MiMo 支持控制台根对象、data 包装和历史 cashBalance 格式', () => {
  assert.equal(parse('mimo', { balance: '8' }).value, 8);
  assert.equal(parse('mimo', { data: { balance: '9' } }).value, 9);
  assert.equal(parse('mimo', { data: { cashBalance: '7.5' } }).value, 7.5);
});

test('七牛返回本月消费，不能把用量当余额猜测', () => {
  assert.equal(parse('qiniu', { data: { total_fee: '5.2' } }).value, 5.2);
  assert.equal(parse('qiniu', { totalFee: 8 }).value, 8);
  assert.throws(() => parse('qiniu', { data: { token_usage: 100 } }), /余额字段/);
});

test('WorkBuddy 积分汇总；合法空账户列表为零', () => {
  const b = parse('workbuddy', { accounts: [{ credits: 10 }, { credits: '25' }] });
  assert.equal(b.value, 35);
  assert.equal(b.currency, 'POINT');
  assert.equal(parse('workbuddy', { accounts: [] }).value, 0);
});

test('WorkBuddy 不把缺少积分的账户偷偷计为零', () => {
  assert.throws(() => parse('workbuddy', { accounts: [{ credits: 12 }, {}] }), /不完整/);
});

test('自定义平台只读取明确的余额路径', () => {
  const a = account('custom', 'custom'); a.path = 'data.accounts[0].wallet.remaining';
  assert.equal(parseBalance(a, '{"data":{"accounts":[{"wallet":{"remaining":"10.5"}}]}}', 1).value, 10.5);
  assert.throws(() => parseBalance(account('custom', 'custom'), '{"usage":99}', 1), /余额字段/);
});

test('平台业务错误和错误 JSON 不产生伪零余额，也不回显响应中的凭证', () => {
  for (const response of [{ success: false, balance: 0 }, { error: 'denied', balance: 0 }, { status: false }]) {
    assert.throws(() => parse('custom', response), /业务错误/);
  }
  const secret = 'synthetic-key-for-redaction-test';
  assert.throws(() => parseBalance(account('custom', 'custom'), secret, 1), error => {
    assert.equal(error.message, '接口没有返回有效 JSON');
    assert.ok(!error.message.includes(secret)); return true;
  });
});

test('零余额有效，缺字段和 null 余额无效', () => {
  assert.equal(parse('custom', { balance: 0 }).hasValue, true);
  assert.throws(() => parse('custom', { balance: null }), /余额字段/);
  assert.throws(() => parse('custom', null), /JSON 对象/);
});

test('接口失效保留旧值和旧时间，标记缓存', () => {
  const a = account(); const old = balance(a, 12.5, 1234);
  const failed = failedBalance(a, old, '凭证失效');
  assert.equal(failed.value, 12.5); assert.equal(failed.updatedAt, 1234);
  assert.equal(failed.hasValue, true); assert.equal(failed.stale, true); assert.equal(failed.ok, false);
});

test('从未查询成功的账户失败后仍为待查询', () => {
  const a = account(); const failed = failedBalance(a, undefined, '失败');
  assert.equal(failed.hasValue, false);
  assert.equal(cardData([a], [failed], 7, 0).value1, '待查询');
  assert.equal(cardData([a], [failed], 7, 0).total, '—');
});

test('不同账户默认相加，相同平台并不会自动合并', () => {
  const one = account('one'); const two = account('two');
  assert.equal(summarize([one, two], [balance(one, 10), balance(two, 20)], 7).cny, 30);
});

test('用户指定同账户组时取最大余额去重', () => {
  const one = account('one'); const two = account('two'); one.group = 'company'; two.group = 'company';
  const s = summarize([one, two], [balance(one, 10), balance(two, 20)], 7);
  assert.equal(s.cny, 20); assert.equal(s.values, 1);
});

test('账户组名与另一条独立账户 ID 相同也不误合并', () => {
  const one = account('same'); const two = account('other'); two.group = 'same';
  assert.equal(summarize([one, two], [balance(one, 10), balance(two, 20)], 7).cny, 30);
});

test('分组不会跨平台合并；美元仅按用户折算率估算', () => {
  const one = account('one'); const two = account('two', 'openrouter'); one.group = 'same'; two.group = 'same';
  assert.equal(summarize([one, two], [balance(one, 10), balance(two, 2)], 7.2).cny, 24.4);
});

test('免费服务、后付费、积分和停用账户排除人民币总额', () => {
  const accounts = ['qiniu', 'modelscope', 'workbuddy'].map(p => account(p, p));
  accounts.forEach(a => { a.includeInTotal = true; });
  const custom = account('points', 'custom'); custom.currency = 'POINT'; accounts.push(custom);
  const disabled = account('disabled'); disabled.enabled = false; accounts.push(disabled);
  assert.equal(summarize(accounts, accounts.map(a => balance(a, 100)), 7).cny, 0);
});

test('汇总展示缓存与未查询数量，拒绝无效折算率', () => {
  const one = account('one'); const two = account('two');
  const s = summarize([one, two], [failedBalance(one, balance(one, 10), '失败')], 7);
  assert.equal(s.cny, 10); assert.equal(s.cached, 1); assert.equal(s.missing, 1);
  for (const rate of [0, -1, NaN, Infinity]) assert.throws(() => summarize([], [], rate), /折算率/);
});

test('新鲜成功查询才写快照，缓存不会造出新历史', () => {
  const a = account(); const b = balance(a, 10);
  assert.equal(sample(undefined, b).value, 10);
  assert.equal(sample(undefined, failedBalance(a, b, '失败')), undefined);
});

test('五分钟内不重复采样；变化后采样，不变六小时采样', () => {
  const a = account(); const old = snapshot(10, 1_000_000);
  assert.equal(sample(old, balance(a, 9, old.timestamp + 4 * minute)), undefined);
  assert.equal(sample(old, balance(a, 9, old.timestamp + 5 * minute)).value, 9);
  assert.equal(sample(old, balance(a, 10, old.timestamp + 5 * minute)), undefined);
  assert.equal(sample(old, balance(a, 10, old.timestamp + 6 * 60 * minute)).value, 10);
});

test('不同账户或币种的快照不影响新基线', () => {
  const a = account();
  assert.ok(sample(snapshot(10, 1_000_000, 'other'), balance(a, 10, 1_000_001)));
  assert.ok(sample(snapshot(10, 1_000_000, 'one', 'USD'), balance(a, 10, 1_000_001)));
});

test('更换凭证后的查询和快照带新修订号，不复用旧基线', () => {
  const a = account('one', 'custom'); a.revision = 2;
  const fresh = parseBalance(a, '{"balance":10}', 1_000_001);
  assert.equal(fresh.revision, 2);
  assert.equal(failedBalance(a, undefined, '失败').revision, 2);
  const point = sample(snapshot(10, 1_000_000), fresh);
  assert.equal(point.revision, 2);
  assert.equal(failedBalance(a, balance(account(), 99), '失败').hasValue, false);
  assert.equal(summarize([a], [balance(account(), 99)], 7).cny, 0);
  assert.equal(cardData([a], [balance(account(), 99)], 7, 0).value1, '待查询');
});

test('消费只由余额下降估计；增加单独记，不猜充值订单', () => {
  const usage = usageOf([snapshot(100, 1), snapshot(80, 2), snapshot(130, 3), snapshot(125, 4)], 'one', 1);
  assert.equal(usage.consumed, 25); assert.equal(usage.increases, 50); assert.equal(usage.points, 4);
});

test('统计按账户、时间排序，跨币种不计算差值', () => {
  const usage = usageOf([snapshot(8, 3, 'one', 'USD'), snapshot(100, 1), snapshot(90, 2), snapshot(999, 2, 'other')], 'one', 1);
  assert.equal(usage.consumed, 10); assert.equal(usage.increases, 0); assert.equal(usage.points, 3);
});

test('区间统计可用区间前的最后一个快照估计首个差值', () => {
  const usage = usageOf([snapshot(100, 1), snapshot(80, 10), snapshot(75, 20)], 'one', 5);
  assert.equal(usage.consumed, 25); assert.equal(usage.points, 2);
});

test('卡片每页四项、页数回绕、免费服务和缓存标识明确', () => {
  const accounts = Array.from({ length: 5 }, (_, i) => account(String(i)));
  const data = cardData(accounts, [], 7, 1);
  assert.equal(data.page, '2/2'); assert.equal(data.name1, accounts[4].label); assert.equal(data.name2, '');
  assert.equal(cardData(accounts, [], 7, 2).page, '1/2');
  assert.equal(cardData(accounts, [], 7, -1).page, '2/2');
  const b = failedBalance(accounts[0], balance(accounts[0], 3), '失败');
  assert.match(cardData(accounts, [b], 7, 0).value1, /缓存/);
  assert.equal(cardData([account('free', 'modelscope')], [], 7, 0).value1, '免费服务');
});

test('卡片数据仅含显示字符串，不含凭证引用或密钥', () => {
  const a = account(); a.secretRef = 'secret-reference-for-test'; a.secretParts = 10;
  const data = cardData([a], [balance(a, 10)], 7, 0);
  assert.ok(Object.values(data).every(v => typeof v === 'string'));
  assert.ok(!JSON.stringify(data).includes(a.secretRef));
  assert.deepEqual(Object.keys(data).sort(), ['total', 'status', 'page', 'name1', 'value1', 'name2', 'value2', 'name3', 'value3', 'name4', 'value4'].sort());
});

test('查询结果合并只覆盖对应账户', () => {
  const one = account('one'); const two = account('two');
  const merged = mergeBalances([balance(one, 10), balance(two, 20)], [balance(one, 12)]);
  assert.equal(merged.length, 2); assert.equal(merged.find(b => b.accountId === 'one').value, 12);
  assert.equal(merged.find(b => b.accountId === 'two').value, 20);
});

test('地址校验拒绝明文传输、内嵌认证、密钥查询参数和替换内置域名', () => {
  const a = account('custom', 'custom');
  for (const url of ['http://localhost:7863/balance', 'https://user:pass@example.com/balance', 'https://example.com/balance?api_key=test', 'https://example.com/\\evil']) {
    a.endpoint = url; assert.throws(() => validateAccount(a));
  }
  a.endpoint = 'https://example.com/v1/balance'; validateAccount(a);
  a.endpoint = 'http://192.168.1.2:7863/balance'; a.allowHttp = true; validateAccount(a);
  a.endpoint = 'http://[::1]:7863/balance'; validateAccount(a);
  const builtin = account(); builtin.endpoint = 'https://example.com/balance'; assert.throws(() => validateAccount(builtin), /不可替换/);
});

test('WorkBuddy 必须指向余额接口，固定平台不能改币种或请求方式', () => {
  const a = account('gateway', 'workbuddy'); a.endpoint = 'https://example.com/panel/api/balance_all'; validateAccount(a);
  a.endpoint = 'https://example.com/v1/chat/completions'; assert.throws(() => validateAccount(a), /balance_all/);
  const usd = account('usd', 'openrouter'); usd.currency = 'CNY'; assert.throws(() => validateAccount(usd), /固定币种/);
  const builtin = account(); builtin.method = 'POST'; assert.throws(() => validateAccount(builtin), /请求方式/);
});

test('金额格式区分人民币、美元、积分和无效金额', () => {
  assert.equal(amount(12, 'CNY'), '¥12.00'); assert.equal(amount(-1.5, 'USD'), '$-1.50');
  assert.equal(amount(12, 'POINT'), '12 积分'); assert.equal(amount(NaN, 'CNY'), '—');
});
