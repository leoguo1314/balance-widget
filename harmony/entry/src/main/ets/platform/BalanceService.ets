import { notificationManager } from '@kit.NotificationKit';
import { formProvider, formBindingData } from '@kit.FormKit';
import { Account, Balance, parseBalance, failedBalance, amount, cardData } from '../core/Core';
import { Repository } from './Repository';
import { NetClient } from './NetClient';

export class BalanceService {
  private repository: Repository;
  private client: NetClient = new NetClient();
  private static pending: Promise<Balance[]> | undefined = undefined;
  private static pendingIds: string[] = [];
  constructor(repository: Repository) { this.repository = repository; }

  async verify(account: Account, credential: string): Promise<Balance> {
    return parseBalance(account, await this.client.query(account, credential), Date.now());
  }

  refresh(ids: string[] = []): Promise<Balance[]> {
    const requested: string[] = ids.length > 0 ? ids : this.repository.state.accounts.filter((a: Account) => a.enabled).map((a: Account) => a.id);
    if (BalanceService.pending) {
      if (requested.every((id: string) => BalanceService.pendingIds.indexOf(id) >= 0)) return BalanceService.pending;
      return BalanceService.pending.then(() => this.refresh(ids));
    }
    BalanceService.pendingIds = requested;
    BalanceService.pending = this.fetchAll(ids).finally(() => { BalanceService.pending = undefined; });
    return BalanceService.pending;
  }

  private async fetchAll(ids: string[]): Promise<Balance[]> {
    const accounts: Account[] = this.repository.state.accounts.filter((a: Account) => a.enabled &&
      (ids.length === 0 || ids.indexOf(a.id) >= 0));
    const results: Balance[] = []; let next: number = 0;
    const worker: () => Promise<void> = async () => {
      while (next < accounts.length) {
        const account: Account = accounts[next++];
        const previous: Balance | undefined = this.repository.state.balances.find((b: Balance) => b.accountId === account.id);
        try {
          if (account.platform === 'modelscope') throw new Error('免费平台，无余额查询接口');
          const credential: string = await this.repository.vault.read(account.secretRef, account.secretParts);
          const balance: Balance = await this.verify(account, credential);
          const latest: Account | undefined = this.repository.state.accounts.find((a: Account) => a.id === account.id);
          if (latest && JSON.stringify(latest) === JSON.stringify(account)) results.push(balance);
        } catch (error) {
          const message: string = error instanceof Error ? error.message : '查询失败，请检查凭证';
          const latest: Account | undefined = this.repository.state.accounts.find((a: Account) => a.id === account.id);
          if (latest && JSON.stringify(latest) === JSON.stringify(account)) {
            results.push(failedBalance(account, previous, message));
          }
        }
      }
    };
    await Promise.all([worker(), worker(), worker(), worker()]);
    await this.repository.updateBalances(results);
    await this.alert(results);
    await this.updateCards();
    return results;
  }

  async updateCards(): Promise<void> {
    for (const form of this.repository.state.forms) {
      try {
        await formProvider.updateForm(form.id, formBindingData.createFormBindingData(cardData(
          this.repository.state.accounts, this.repository.state.balances, this.repository.state.settings.usdCny, form.page)));
      } catch (_) { /* 卡片可能已被桌面移除，不影响查询结果。 */ }
    }
  }

  private async alert(results: Balance[]): Promise<void> {
    if (!this.repository.state.settings.notifications) return;
    for (const balance of results) {
      const account: Account | undefined = this.repository.state.accounts.find((a: Account) => a.id === balance.accountId);
      if (!account || !balance.ok || !balance.hasValue || balance.value >= account.threshold || !account.includeInTotal) continue;
      const last: number = this.repository.state.alerts[account.id] || 0;
      if (Date.now() - last < 86400000) continue;
      try {
        await notificationManager.publish({
          id: 1000 + this.repository.state.accounts.indexOf(account),
          content: { contentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
            normal: { title: account.label + ' 余额提醒', text: '当前余额 ' + amount(balance.value, balance.currency) + '，低于设定阈值' } }
        });
        this.repository.state.alerts[account.id] = Date.now();
      } catch (_) { /* 用户可能关闭通知授权，不改变余额状态。 */ }
    }
    await this.repository.save();
  }
}
