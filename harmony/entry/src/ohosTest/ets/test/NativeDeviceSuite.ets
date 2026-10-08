import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { preferences, relationalStore } from '@kit.ArkData';
import { Account, Balance, Snapshot, Summary, newAccount, parseBalance, summarize } from '../../../main/ets/core/Core';
import { Vault, SecretReference } from '../../../main/ets/platform/Vault';
import { HistoryStore } from '../../../main/ets/platform/HistoryStore';
import { Repository, ReportExport } from '../../../main/ets/platform/Repository';

function check(condition: boolean): void {
  if (!condition) throw new Error('Native assertion failed');
}

/** No arbitrary exception name, message, stack, path, or credential reaches the test log. */
export function describeNativeFailure(error: Error): string {
  const rawCode: number = (error as BusinessError)?.code;
  const code: number = typeof rawCode === 'number' && Number.isFinite(rawCode) ? rawCode : -1;
  const rawName: string = error?.name;
  const name: string = rawName === 'Error' || rawName === 'TypeError' || rawName === 'RangeError' ? rawName : 'Other';
  let reason: string = code !== -1 ? 'NativeBusinessError' : 'UnclassifiedException';
  if (name === 'TypeError') reason = 'InvalidRuntimeValue';
  else if (name === 'RangeError') reason = 'InvalidRuntimeRange';
  // Classification may inspect an exception, but only fixed labels can reach the log.
  else if (error?.message === 'Native assertion failed') reason = 'AssertionFailed';
  else if (error?.message === 'Asset removal assertion failed') reason = 'AssetRemovalFailed';
  else if (typeof error?.message === 'string') {
    if (/permission|denied|not permitted/i.test(error.message)) reason = 'PermissionFailure';
    else if (/context|stage/i.test(error.message)) reason = 'ContextUnsupported';
    else if (/database|sqlite|rdb/i.test(error.message)) reason = 'DatabaseFailure';
    else if (/preferences|preference/i.test(error.message)) reason = 'PreferencesFailure';
    else if (/argument|parameter/i.test(error.message)) reason = 'NativeParameterFailure';
    else if (/path|directory|file/i.test(error.message)) reason = 'StoragePathFailure';
  }
  return ' code=' + code + ' name=' + name + ' reason=' + reason;
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
  private stage: string = 'Begin';

  constructor(delegator: abilityDelegatorRegistry.AbilityDelegator) {
    this.delegator = delegator;
  }

  private async runCase(name: string, action: () => Promise<void>): Promise<number> {
    let failed: number = 0;
    let diagnostic: string = '';
    this.stage = 'Begin';
    try { await action(); } catch (error) {
      failed = 1;
      diagnostic = ' stage=' + this.stage + describeNativeFailure(error as Error);
    }
    await this.delegator.print((failed === 0 ? 'PASS ' : 'FAIL ') + name + diagnostic + '\n');
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
    const contextFailure: number = await this.runCase('ContextReady', async () => {
      this.stage = 'ContextReady';
      const present: boolean = context !== undefined && context !== null;
      const stageMode: boolean = present && context.stageMode === true;
      const databaseDir: boolean = present && typeof context.databaseDir === 'string' && context.databaseDir.length > 0;
      const preferencesDir: boolean = present && typeof context.preferencesDir === 'string' && context.preferencesDir.length > 0;
      await this.delegator.print('DIAG ContextReady present=' + present + ' databaseDir=' + databaseDir +
        ' preferencesDir=' + preferencesDir + ' stageMode=' + stageMode + '\n');
      check(present && databaseDir && preferencesDir && stageMode);
      this.stage = 'ArkDataReady';
      const preferencesReady: boolean = typeof preferences.getPreferencesSync === 'function';
      const relationalReady: boolean = typeof relationalStore.getRdbStore === 'function';
      await this.delegator.print('DIAG ArkDataReady preferencesAPI=' + preferencesReady +
        ' relationalAPI=' + relationalReady + '\n');
      check(preferencesReady && relationalReady);
    });
    failed += contextFailure;
    // Missing native context or API exports must fail before opening either isolated store.
    if (contextFailure !== 0) return failed;
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
      this.stage = 'WriteShort';
      shortReference = await vault.write(shortSecret);
      this.stage = 'WriteUnicode';
      unicodeReference = await vault.write(unicodeSecret);
      this.stage = 'CheckParts';
      check(shortReference.parts === 1 && unicodeReference.parts >= 3);
      this.stage = 'ReadShort';
      check(await vault.read(shortReference.name, shortReference.parts) === shortSecret);
      this.stage = 'ReadUnicode';
      check(await vault.read(unicodeReference.name, unicodeReference.parts) === unicodeSecret);
      this.stage = 'RemoveShort';
      await vault.remove(shortReference.name, shortReference.parts);
      await checkRemoved(shortReference);
      this.stage = 'RemoveUnicode';
      await vault.remove(unicodeReference.name, unicodeReference.parts);
      await checkRemoved(unicodeReference);
    } finally {
      const previousStage: string = this.stage;
      this.stage = 'CleanupAssets';
      // Only references returned by this test's own writes are eligible for cleanup.
      const references: SecretReference[] = [];
      if (shortReference) references.push(shortReference);
      if (unicodeReference) references.push(unicodeReference);
      await cleanReferences(vault, references);
      this.stage = previousStage;
    }
  }

  private async testHistory(context: common.Context): Promise<void> {
    this.stage = 'CreateIsolatedStore';
    const databaseName: string = 'native-history-' + util.generateRandomUUID().toLowerCase() + '.db';
    check(/^native-history-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.db$/.test(databaseName));
    const id: string = 'native-history-' + util.generateRandomUUID();
    const history: HistoryStore = new HistoryStore(context, databaseName);
    const balance: Balance = new Balance();
    balance.accountId = id; balance.value = 20; balance.currency = 'CNY';
    balance.ok = true; balance.hasValue = true; balance.updatedAt = Date.now();
    this.stage = 'ReadEmptyStore';
    check((await history.all()).length === 0);
    try {
      this.stage = 'RecordFirst';
      await history.record(balance);
      balance.value = 15; balance.updatedAt += 6 * 60000;
      this.stage = 'RecordSecond';
      await history.record(balance);
      this.stage = 'ReopenAndRead';
      const reopened: HistoryStore = new HistoryStore(context, databaseName);
      const points: Snapshot[] = (await reopened.all()).filter((point: Snapshot) => point.accountId === id);
      check(points.length === 2 && points[0].value === 20 && points[1].value === 15);
      check(points[0].currency === 'CNY' && points[1].revision === 0);
      this.stage = 'RemoveAndRead';
      await reopened.remove(id);
      check(!(await new HistoryStore(context, databaseName).all()).some((point: Snapshot) => point.accountId === id));
    } finally {
      const previousStage: string = this.stage;
      this.stage = 'CleanupHistory';
      await history.remove(id);
      check(!(await history.all()).some((point: Snapshot) => point.accountId === id));
      this.stage = previousStage;
    }
  }

  private async testRepository(context: common.Context): Promise<void> {
    // A fresh instance reads persisted preferences; never use the production shared singleton.
    this.stage = 'CreateIsolatedStore';
    const preferencesName: string = 'native-repository-' + util.generateRandomUUID().toLowerCase();
    check(/^native-repository-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(preferencesName));
    const databaseName: string = preferencesName + '.db';
    const repository: Repository = new Repository(context, preferencesName, databaseName);
    const before: string = JSON.stringify(repository.state);
    check(repository.state.accounts.length === 0 && repository.state.balances.length === 0);
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
      this.stage = 'SaveAccount';
      await repository.saveAccount(account, firstSecret);
      references.push(referenceOf(account));
      this.stage = 'ReopenAccount';
      const reopened: Repository = new Repository(context, preferencesName, databaseName);
      const stored: Account | undefined = reopened.state.accounts.find((item: Account) => item.id === id);
      check(stored !== undefined);
      if (!stored) throw new Error('Native assertion failed');
      check(stored.label === account.label && stored.secretRef === account.secretRef);
      this.stage = 'ReadCredential';
      check(await reopened.vault.read(stored.secretRef, stored.secretParts) === firstSecret);
      edited = copyAccount(stored); edited.label = 'Native edited account';
      this.stage = 'EditAndKeepCredential';
      await reopened.saveAccount(edited, '');
      const editedStored: Account | undefined = new Repository(context, preferencesName, databaseName).state.accounts.find((item: Account) => item.id === id);
      check(editedStored !== undefined);
      if (!editedStored) throw new Error('Native assertion failed');
      check(editedStored.label === edited.label && editedStored.secretRef === stored.secretRef && editedStored.revision === stored.revision);
      replacement = copyAccount(editedStored);
      this.stage = 'ReplaceCredential';
      await reopened.saveAccount(replacement, secondSecret);
      references.push(referenceOf(replacement));
      check(replacement.revision === stored.revision + 1);
      this.stage = 'CheckCredentialReplacement';
      await checkRemoved(referenceOf(stored));
      check(await reopened.vault.read(replacement.secretRef, replacement.secretParts) === secondSecret);
      const balance: Balance = new Balance();
      balance.accountId = id; balance.value = 8.75; balance.currency = 'CNY';
      balance.ok = true; balance.hasValue = true; balance.updatedAt = Date.now(); balance.revision = replacement.revision;
      this.stage = 'PersistBalance';
      await reopened.updateBalances([balance]);
      this.stage = 'ReopenBalance';
      const persisted: Repository = new Repository(context, preferencesName, databaseName);
      check(persisted.state.balances.some((item: Balance) => item.accountId === id && item.value === 8.75));
      check((await persisted.history.all()).some((point: Snapshot) => point.accountId === id && point.revision === replacement?.revision));
      this.stage = 'Export';
      const reportText: string = await persisted.exportReport();
      const report: ReportExport = JSON.parse(reportText) as ReportExport;
      const exported: Account | undefined = report.accounts.find((item: Account) => item.id === id);
      check(exported !== undefined && exported.secretRef === '' && exported.secretParts === 0);
      check(reportText.indexOf(firstSecret) < 0 && reportText.indexOf(secondSecret) < 0);
      this.stage = 'RemoveAccount';
      await persisted.removeAccount(id);
      const removed: Repository = new Repository(context, preferencesName, databaseName);
      check(!removed.state.accounts.some((item: Account) => item.id === id));
      check(!removed.state.balances.some((item: Balance) => item.accountId === id));
      check(!(await removed.history.all()).some((point: Snapshot) => point.accountId === id));
      await checkRemoved(referenceOf(replacement));
    } finally {
      const previousStage: string = this.stage;
      // saveAccount can mutate the supplied reference before a later operation fails.
      if (account.secretRef) references.push(referenceOf(account));
      if (edited?.secretRef) references.push(referenceOf(edited));
      if (replacement?.secretRef) references.push(referenceOf(replacement));
      let cleanupFailed: boolean = false;
      this.stage = 'CleanupAccount';
      try {
        const cleanup: Repository = new Repository(context, preferencesName, databaseName);
        if (cleanup.state.accounts.some((item: Account) => item.id === id)) await cleanup.removeAccount(id);
      } catch (_) { cleanupFailed = true; }
      const cleanupHistory: HistoryStore = new HistoryStore(context, databaseName);
      try { await cleanupHistory.remove(id); } catch (_) { cleanupFailed = true; }
      try { await cleanReferences(new Vault(), references); } catch (_) { cleanupFailed = true; }
      try {
        check(JSON.stringify(new Repository(context, preferencesName, databaseName).state) === before);
        check(!(await cleanupHistory.all()).some((point: Snapshot) => point.accountId === id));
      } catch (_) { cleanupFailed = true; }
      check(!cleanupFailed);
      this.stage = previousStage;
    }
  }
}
