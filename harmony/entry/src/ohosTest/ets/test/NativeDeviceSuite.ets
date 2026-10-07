import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Account, Balance, Snapshot, Summary, newAccount, parseBalance, summarize } from '../../../main/ets/core/Core';
import { Vault, SecretReference } from '../../../main/ets/platform/Vault';
import { HistoryStore } from '../../../main/ets/platform/HistoryStore';
import { Repository, ReportExport } from '../../../main/ets/platform/Repository';

function check(condition: boolean): void {
  if (!condition) throw new Error('Native assertion failed');
}

function copyAccount(account: Account): Account {
  return JSON.parse(JSON.stringify(account)) as Account;
}

function referenceOf(account: Account): SecretReference {
  const reference: SecretReference = new SecretReference();
  reference.name = account.secretRef;
  reference.parts = account.secretParts;
  return reference;
}

async function checkRemoved(reference: SecretReference): Promise<void> {
  for (let index: number = 0; index < reference.parts; index++) {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto(reference.name + '-' + index));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ATTRIBUTES);
    try {
      const rows: asset.AssetMap[] = await asset.query(query);
      check(rows.length === 0);
    } catch (error) {
      // An unavailable/locked AssetStore is a failure, not evidence of successful removal.
      if ((error as BusinessError).code !== asset.ErrorCode.NOT_FOUND) throw new Error('Asset removal assertion failed');
    }
  }
}

async function cleanReferences(vault: Vault, references: SecretReference[]): Promise<void> {
  let failed: boolean = false;
  // Attempt every owned reference even if an earlier cleanup query fails.
  for (const reference of references) {
    try {
      await vault.remove(reference.name, reference.parts);
      await checkRemoved(reference);
    } catch (_) { failed = true; }
  }
  check(!failed);
}

export class NativeDeviceSuite {
  private delegator: abilityDelegatorRegistry.AbilityDelegator;

  constructor(delegator: abilityDelegatorRegistry.AbilityDelegator) {
    this.delegator = delegator;
  }

  private async runCase(name: string, action: () => Promise<void>): Promise<number> {
    let failed: number = 0;
    try { await action(); } catch (_) { failed = 1; }
    await this.delegator.print((failed === 0 ? 'PASS ' : 'FAIL ') + name + '\n');
    return failed;
  }

  async runCore(): Promise<number> {
    return this.runCase('CoreParsingAndGrouping', async () => {
      const first: Account = newAccount('core-first', 'deepseek');
      const duplicate: Account = newAccount('core-duplicate', 'deepseek');
      const usd: Account = newAccount('core-usd', 'openrouter');
      first.group = 'synthetic-group'; duplicate.group = 'synthetic-group';
      const timestamp: number = Date.now();
      const firstBalance: Balance = parseBalance(first,
        '{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"12.50"}]}', timestamp);
      const duplicateBalance: Balance = parseBalance(duplicate,
        '{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"10.00"}]}', timestamp);
      const usdBalance: Balance = parseBalance(usd, '{"data":{"total_credits":5,"total_usage":2}}', timestamp);
      check(firstBalance.ok && firstBalance.hasValue && firstBalance.value === 12.5 && firstBalance.currency === 'CNY');
      check(usdBalance.value === 3 && usdBalance.currency === 'USD');
      const summary: Summary = summarize([first, duplicate, usd], [firstBalance, duplicateBalance, usdBalance], 7.2);
      check(summary.values === 2 && Math.abs(summary.cny - 34.1) < 0.000001 && summary.missing === 0);
      let rejected: boolean = false;
      try { parseBalance(first, '{"success":false}', timestamp); } catch (_) { rejected = true; }
      check(rejected);
    });
  }

  async runStorage(context: common.Context): Promise<number> {
    let failed: number = 0;
    failed += await this.runCase('VaultUnicodeRoundTrip', () => this.testVault());
    failed += await this.runCase('HistoryPersistence', () => this.testHistory(context));
    failed += await this.runCase('RepositoryLifecycle', () => this.testRepository(context));
    return failed;
  }

  private async testVault(): Promise<void> {
    const vault: Vault = new Vault();
    const shortSecret: string = 'synthetic-' + util.generateRandomUUID();
    // The first Chinese UTF-8 character crosses the 900-byte asset boundary (899 + 3 bytes).
    const unicodeSecret: string = 'a'.repeat(899) + '汉🙂字'.repeat(250) + '-synthetic';
    let shortReference: SecretReference | undefined = undefined;
    let unicodeReference: SecretReference | undefined = undefined;
    try {
      shortReference = await vault.write(shortSecret);
      unicodeReference = await vault.write(unicodeSecret);
      check(shortReference.parts === 1 && unicodeReference.parts >= 3);
      check(await vault.read(shortReference.name, shortReference.parts) === shortSecret);
      check(await vault.read(unicodeReference.name, unicodeReference.parts) === unicodeSecret);
      await vault.remove(shortReference.name, shortReference.parts);
      await checkRemoved(shortReference);
      await vault.remove(unicodeReference.name, unicodeReference.parts);
      await checkRemoved(unicodeReference);
    } finally {
      // Only references returned by this test's own writes are eligible for cleanup.
      const references: SecretReference[] = [];
      if (shortReference) references.push(shortReference);
      if (unicodeReference) references.push(unicodeReference);
      await cleanReferences(vault, references);
    }
  }

  private async testHistory(context: common.Context): Promise<void> {
    const id: string = 'native-history-' + util.generateRandomUUID();
    const history: HistoryStore = new HistoryStore(context);
    const balance: Balance = new Balance();
    balance.accountId = id; balance.value = 20; balance.currency = 'CNY';
    balance.ok = true; balance.hasValue = true; balance.updatedAt = Date.now();
    check(!(await history.all()).some((point: Snapshot) => point.accountId === id));
    try {
      await history.record(balance);
      balance.value = 15; balance.updatedAt += 6 * 60000;
      await history.record(balance);
      const reopened: HistoryStore = new HistoryStore(context);
      const points: Snapshot[] = (await reopened.all()).filter((point: Snapshot) => point.accountId === id);
      check(points.length === 2 && points[0].value === 20 && points[1].value === 15);
      check(points[0].currency === 'CNY' && points[1].revision === 0);
      await reopened.remove(id);
      check(!(await new HistoryStore(context).all()).some((point: Snapshot) => point.accountId === id));
    } finally {
      await history.remove(id);
      check(!(await history.all()).some((point: Snapshot) => point.accountId === id));
    }
  }

  private async testRepository(context: common.Context): Promise<void> {
    // A fresh instance reads persisted preferences; never use the production shared singleton.
    const repository: Repository = new Repository(context);
    const before: string = JSON.stringify(repository.state);
    const id: string = 'native-account-' + util.generateRandomUUID();
    const account: Account = newAccount(id, 'deepseek');
    account.label = 'Native synthetic account';
    const firstSecret: string = 'synthetic-first-' + util.generateRandomUUID();
    const secondSecret: string = 'synthetic-second-' + util.generateRandomUUID();
    const references: SecretReference[] = [];
    let edited: Account | undefined = undefined;
    let replacement: Account | undefined = undefined;
    check(!repository.state.accounts.some((item: Account) => item.id === id));
    try {
      await repository.saveAccount(account, firstSecret);
      references.push(referenceOf(account));
      const reopened: Repository = new Repository(context);
      const stored: Account | undefined = reopened.state.accounts.find((item: Account) => item.id === id);
      check(stored !== undefined);
      if (!stored) throw new Error('Native assertion failed');
      check(stored.label === account.label && stored.secretRef === account.secretRef);
      check(await reopened.vault.read(stored.secretRef, stored.secretParts) === firstSecret);
      edited = copyAccount(stored); edited.label = 'Native edited account';
      await reopened.saveAccount(edited, '');
      const editedStored: Account | undefined = new Repository(context).state.accounts.find((item: Account) => item.id === id);
      check(editedStored !== undefined);
      if (!editedStored) throw new Error('Native assertion failed');
      check(editedStored.label === edited.label && editedStored.secretRef === stored.secretRef && editedStored.revision === stored.revision);
      replacement = copyAccount(editedStored);
      await reopened.saveAccount(replacement, secondSecret);
      references.push(referenceOf(replacement));
      check(replacement.revision === stored.revision + 1);
      await checkRemoved(referenceOf(stored));
      check(await reopened.vault.read(replacement.secretRef, replacement.secretParts) === secondSecret);
      const balance: Balance = new Balance();
      balance.accountId = id; balance.value = 8.75; balance.currency = 'CNY';
      balance.ok = true; balance.hasValue = true; balance.updatedAt = Date.now(); balance.revision = replacement.revision;
      await reopened.updateBalances([balance]);
      const persisted: Repository = new Repository(context);
      check(persisted.state.balances.some((item: Balance) => item.accountId === id && item.value === 8.75));
      check((await persisted.history.all()).some((point: Snapshot) => point.accountId === id && point.revision === replacement?.revision));
      const reportText: string = await persisted.exportReport();
      const report: ReportExport = JSON.parse(reportText) as ReportExport;
      const exported: Account | undefined = report.accounts.find((item: Account) => item.id === id);
      check(exported !== undefined && exported.secretRef === '' && exported.secretParts === 0);
      check(reportText.indexOf(firstSecret) < 0 && reportText.indexOf(secondSecret) < 0);
      await persisted.removeAccount(id);
      const removed: Repository = new Repository(context);
      check(!removed.state.accounts.some((item: Account) => item.id === id));
      check(!removed.state.balances.some((item: Balance) => item.accountId === id));
      check(!(await removed.history.all()).some((point: Snapshot) => point.accountId === id));
      await checkRemoved(referenceOf(replacement));
    } finally {
      // saveAccount can mutate the supplied reference before a later operation fails.
      if (account.secretRef) references.push(referenceOf(account));
      if (edited?.secretRef) references.push(referenceOf(edited));
      if (replacement?.secretRef) references.push(referenceOf(replacement));
      let cleanupFailed: boolean = false;
      try {
        const cleanup: Repository = new Repository(context);
        if (cleanup.state.accounts.some((item: Account) => item.id === id)) await cleanup.removeAccount(id);
      } catch (_) { cleanupFailed = true; }
      const cleanupHistory: HistoryStore = new HistoryStore(context);
      try { await cleanupHistory.remove(id); } catch (_) { cleanupFailed = true; }
      try { await cleanReferences(new Vault(), references); } catch (_) { cleanupFailed = true; }
      try {
        check(JSON.stringify(new Repository(context).state) === before);
        check(!(await cleanupHistory.all()).some((point: Snapshot) => point.accountId === id));
      } catch (_) { cleanupFailed = true; }
      check(!cleanupFailed);
    }
  }
}
