import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Account, Balance, Snapshot, validateAccount, mergeBalances } from '../core/Core';
import { Vault, SecretReference } from './Vault';
import { HistoryStore } from './HistoryStore';

export class Settings {
  usdCny: number = 7.2;
  refreshMinutes: number = 5;
  notifications: boolean = false;
}
export class FormInstance { id: string = ''; page: number = 0; }
export class LocalState {
  version: number = 1;
  accounts: Account[] = [];
  balances: Balance[] = [];
  settings: Settings = new Settings();
  forms: FormInstance[] = [];
  alerts: Record<string, number> = {};
}

export class Repository {
  private static shared: Repository | undefined = undefined;
  static open(context: common.Context): Repository {
    if (!Repository.shared) Repository.shared = new Repository(context);
    return Repository.shared;
  }
  private prefs: preferences.Preferences;
  vault: Vault = new Vault();
  history: HistoryStore;
  state: LocalState;
  constructor(context: common.Context) {
    this.prefs = preferences.getPreferencesSync(context, { name: 'balance-harmony' });
    this.history = new HistoryStore(context);
    const raw: string = this.prefs.getSync('state', '') as string;
    this.state = raw ? JSON.parse(raw) as LocalState : new LocalState();
    if (this.state.version !== 1 || !Array.isArray(this.state.accounts) || !Array.isArray(this.state.balances)) {
      throw new Error('本地数据格式不兼容，请先导出数据后处理');
    }
  }

  async save(): Promise<void> {
    this.prefs.putSync('state', JSON.stringify(this.state));
    await this.prefs.flush();
  }

  async saveAccount(account: Account, credential: string): Promise<void> {
    validateAccount(account);
    const previous: Account | undefined = this.state.accounts.find((a: Account) => a.id === account.id);
    if (!previous && this.state.accounts.length >= 50) throw new Error('最多可配置 50 个凭证');
    let fresh: SecretReference | undefined = undefined;
    if (credential) {
      fresh = await this.vault.write(credential);
      account.secretRef = fresh.name; account.secretParts = fresh.parts;
    } else if (previous && previous.platform === account.platform && previous.endpoint === account.endpoint) {
      account.secretRef = previous.secretRef; account.secretParts = previous.secretParts;
    } else {
      account.secretRef = ''; account.secretParts = 0;
    }
    if (account.platform !== 'modelscope' && account.platform !== 'mimo' && !account.secretRef) {
      throw new Error('请输入 API 凭证');
    }
    const before: LocalState = JSON.parse(JSON.stringify(this.state)) as LocalState;
    // 换平台/接口/币种后不能拿旧数伪装成新账户余额。
    const reset: boolean = previous !== undefined && (previous.platform !== account.platform || previous.endpoint !== account.endpoint ||
      previous.currency !== account.currency || previous.path !== account.path || previous.method !== account.method || previous.secretRef !== account.secretRef);
    account.revision = previous ? (previous.revision || 0) + (reset ? 1 : 0) : 0;
    const index: number = this.state.accounts.findIndex((a: Account) => a.id === account.id);
    const saved: Account = JSON.parse(JSON.stringify(account)) as Account;
    if (index >= 0) this.state.accounts[index] = saved; else this.state.accounts.push(saved);
    if (reset) {
      this.state.balances = this.state.balances.filter((b: Balance) => b.accountId !== account.id);
    }
    try { await this.save(); } catch (_) {
      this.state = before;
      if (fresh) await this.vault.remove(fresh.name, fresh.parts);
      throw new Error('配置保存失败，旧凭证仍保留');
    }
    if (previous && previous.secretRef !== account.secretRef) await this.vault.remove(previous.secretRef, previous.secretParts);
    if (reset) await this.history.remove(account.id);
  }

  async removeAccount(id: string): Promise<void> {
    const existing: Account | undefined = this.state.accounts.find((a: Account) => a.id === id);
    const before: LocalState = JSON.parse(JSON.stringify(this.state)) as LocalState;
    this.state.accounts = this.state.accounts.filter((a: Account) => a.id !== id);
    this.state.balances = this.state.balances.filter((b: Balance) => b.accountId !== id);
    try { await this.save(); } catch (_) { this.state = before; throw new Error('删除失败，请重试'); }
    if (existing) await this.vault.remove(existing.secretRef, existing.secretParts);
    await this.history.remove(id);
  }

  async updateBalances(results: Balance[]): Promise<void> {
    const valid: Balance[] = results.filter((b: Balance) => this.state.accounts.some((a: Account) =>
      a.id === b.accountId && a.enabled && a.revision === b.revision));
    this.state.balances = mergeBalances(this.state.balances, valid);
    await this.save();
    for (const result of valid) await this.history.record(result);
  }

  async setForm(id: string, page: number): Promise<void> {
    const form: FormInstance = new FormInstance(); form.id = id; form.page = page;
    this.state.forms = this.state.forms.filter((item: FormInstance) => item.id !== id);
    this.state.forms.push(form);
    await this.save();
  }

  async removeForm(id: string): Promise<void> {
    this.state.forms = this.state.forms.filter((item: FormInstance) => item.id !== id);
    await this.save();
  }

  async exportReport(): Promise<string> {
    const records: Snapshot[] = (await this.history.all()).filter((p: Snapshot) => this.state.accounts.some((a: Account) =>
      a.id === p.accountId && a.revision === p.revision));
    const data: ReportExport = new ReportExport();
    data.exportedAt = new Date().toISOString(); data.history = records;
    data.settings.usdCny = this.state.settings.usdCny;
    data.settings.refreshMinutes = this.state.settings.refreshMinutes;
    data.settings.notifications = this.state.settings.notifications;
    // 明确只导出统计和非凭证配置；跨设备迁移需要重新输入 Key。
    data.accounts = this.state.accounts.map((a: Account) => {
      const copy: Account = JSON.parse(JSON.stringify(a)) as Account;
      copy.secretRef = ''; copy.secretParts = 0; return copy;
    });
    return JSON.stringify(data, null, 2);
  }
}

export class ReportExport {
  app: string = 'balance-widget-harmony';
  format: number = 1;
  exportedAt: string = '';
  accounts: Account[] = [];
  settings: Settings = new Settings();
  history: Snapshot[] = [];
}
