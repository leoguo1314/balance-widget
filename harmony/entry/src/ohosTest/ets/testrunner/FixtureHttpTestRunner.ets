import { abilityDelegatorRegistry, TestRunner } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Account, Balance, Snapshot, newAccount } from '../../../main/ets/core/Core';
import { BalanceService } from '../../../main/ets/platform/BalanceService';
import { Repository } from '../../../main/ets/platform/Repository';
import { Vault } from '../../../main/ets/platform/Vault';

const FIXTURE_ORIGIN: string = 'http://127.0.0.1:41727';
const SYNTHETIC_CREDENTIAL: string = 'synthetic-device-validation';

function check(condition: boolean): void {
  if (!condition) throw new Error('Fixture assertion failed');
}

class FixtureControl {
  balance: number = 100;
  httpStatus: number = 200;
  delayMs: number = 0;
}

class FixtureStatus {
  name: string = '';
  status: string = '';
  control: FixtureControl = new FixtureControl();
}

/** Only fixed phase labels and numeric business codes are permitted in diagnostics. */
function failureCode(error: Error): number {
  const code: number = (error as BusinessError)?.code;
  return typeof code === 'number' && Number.isFinite(code) ? code : -1;
}

class FixtureHttpSuite {
  stage: string = 'Begin';
  passed: string[] = [];
  failures: string[] = [];

  private cleanupFailure(stage: string, error: Error): void {
    this.failures.push('FAIL FixtureHttpCleanup stage=' + stage + ' code=' + failureCode(error));
  }

  private async control(balance: number, status: number, delayMs: number): Promise<void> {
    const request: http.HttpRequest = http.createHttp();
    const change: FixtureControl = new FixtureControl();
    change.balance = balance; change.httpStatus = status; change.delayMs = delayMs;
    const headers: Record<string, string> = {};
    headers['Content-Type'] = 'application/json';
    headers['Accept'] = 'application/json';
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST, header: headers, extraData: JSON.stringify(change),
        expectDataType: http.HttpDataType.STRING, connectTimeout: 3000, readTimeout: 3000,
        usingCache: false, maxRedirects: 0, maxLimit: 4096
      };
      const reply: http.HttpResponse = await request.request(FIXTURE_ORIGIN + '/control', options);
      check(reply.responseCode === 200 && typeof reply.result === 'string');
      const result: FixtureStatus = JSON.parse(reply.result as string) as FixtureStatus;
      check(result.name === 'balance-widget-device-fixture' && result.status === 'listening');
      check(result.control.balance === balance && result.control.httpStatus === status && result.control.delayMs === delayMs);
    } finally {
      request.destroy();
    }
  }

  private balance(results: Balance[], account: Account): Balance {
    check(results.length === 1);
    const result: Balance = results[0];
    check(result.accountId === account.id && result.revision === account.revision && result.currency === 'CNY');
    return result;
  }

  private cached(result: Balance, previous: Balance): void {
    check(!result.ok && result.hasValue && result.stale);
    check(result.value === previous.value && result.updatedAt === previous.updatedAt);
    check(result.error.length > 0);
  }

  private async removedAsset(name: string, parts: number): Promise<void> {
    for (let index: number = 0; index < parts; index++) {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto(name + '-' + index));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ATTRIBUTES);
      try {
        check((await asset.query(query)).length === 0);
      } catch (error) {
        if ((error as BusinessError).code !== asset.ErrorCode.NOT_FOUND) throw new Error('Fixture cleanup failed');
      }
    }
  }

  async run(context: common.ApplicationContext): Promise<void> {
    this.stage = 'CreateIsolatedRepository';
    check(context.stageMode === true);
    const preferencesName: string = 'fixture-http-' + util.generateRandomUUID().toLowerCase();
    check(/^fixture-http-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(preferencesName));
    const databaseName: string = preferencesName + '.db';
    const repository: Repository = new Repository(context, preferencesName, databaseName);
    check(repository.state.accounts.length === 0 && repository.state.balances.length === 0);
    repository.state.settings.notifications = false;
    repository.state.forms = [];
    const before: string = JSON.stringify(repository.state);
    const account: Account = newAccount('fixture-http-' + util.generateRandomUUID(), 'custom');
    account.label = 'Native synthetic HTTP fixture';
    account.endpoint = FIXTURE_ORIGIN + '/balance'; account.path = 'balance';
    account.method = 'GET'; account.currency = 'CNY'; account.allowHttp = true;
    const service: BalanceService = new BalanceService(repository);
    let operationFailed: boolean = false;
    try {
      this.stage = 'SaveSyntheticAccount';
      await repository.saveAccount(account, SYNTHETIC_CREDENTIAL);
      check(account.secretRef.length > 0 && account.secretParts === 1);
      check(await repository.vault.read(account.secretRef, account.secretParts) === SYNTHETIC_CREDENTIAL);
      this.stage = 'ControlSuccess';
      await this.control(100, 200, 0);
      this.stage = 'HttpSuccess';
      const first: Balance = this.balance(await service.refresh([account.id]), account);
      check(first.ok && first.hasValue && !first.stale && first.value === 100 && first.updatedAt > 0 && first.error === '');
      const firstHistory: Snapshot[] = await repository.history.all();
      check(firstHistory.length === 1 && firstHistory[0].accountId === account.id && firstHistory[0].value === 100);
      check(firstHistory[0].timestamp === first.updatedAt && firstHistory[0].revision === account.revision);
      this.passed.push('FixtureHttpSuccessAndHistory');

      this.stage = 'ControlHttpFailure';
      await this.control(0, 503, 0);
      this.stage = 'HttpFailureCache';
      const failed: Balance = this.balance(await service.refresh([account.id]), account);
      this.cached(failed, first);
      check(failed.error === '平台响应 HTTP 503');
      check(JSON.stringify(await repository.history.all()) === JSON.stringify(firstHistory));
      const failedReopen: Repository = new Repository(context, preferencesName, databaseName);
      check(failedReopen.state.balances.length === 1);
      this.cached(failedReopen.state.balances[0], first);
      this.passed.push('FixtureHttp503RetainsPersistedCache');

      this.stage = 'ControlRecovery';
      await this.control(42.5, 200, 0);
      this.stage = 'HttpRecovery';
      const recovered: Balance = this.balance(await service.refresh([account.id]), account);
      check(recovered.ok && recovered.hasValue && !recovered.stale && recovered.value === 42.5);
      check(recovered.updatedAt >= first.updatedAt && recovered.error === '');
      const recoveredReopen: Repository = new Repository(context, preferencesName, databaseName);
      check(recoveredReopen.state.balances.length === 1 && recoveredReopen.state.balances[0].value === 42.5);
      check(recoveredReopen.state.balances[0].ok && !recoveredReopen.state.balances[0].stale);
      // Production HistoryStore samples at most once per five minutes; this fast recovery is persisted as a balance.
      check(recovered.updatedAt - first.updatedAt < 5 * 60000);
      check(JSON.stringify(await repository.history.all()) === JSON.stringify(firstHistory));
      this.passed.push('FixtureHttpRecoveryAndSampling');

      this.stage = 'ControlTimeout';
      await this.control(9, 200, 8000);
      this.stage = 'HttpTimeoutCache';
      const started: number = Date.now();
      const timedOut: Balance = this.balance(await service.refresh([account.id]), account);
      const duration: number = Date.now() - started;
      this.cached(timedOut, recovered);
      // Covers either the native 4-second read limit or the 7-second application deadline.
      check(duration >= 2500 && duration < 10000);
      check(JSON.stringify(await repository.history.all()) === JSON.stringify(firstHistory));
      const timeoutReopen: Repository = new Repository(context, preferencesName, databaseName);
      check(timeoutReopen.state.balances.length === 1);
      this.cached(timeoutReopen.state.balances[0], recovered);
      this.passed.push('FixtureHttpTimeoutRetainsPersistedCache');
    } catch (error) {
      operationFailed = true;
      this.failures.push('FAIL FixtureHttpOperation stage=' + this.stage + ' code=' + failureCode(error as Error));
      // Preserve only safe failure text; the original phase/code remain available even if cleanup also fails.
      throw new Error('Fixture operation failed');
    } finally {
      let failed: boolean = false;
      try { await this.control(100, 200, 0); } catch (error) {
        failed = true; this.cleanupFailure('ResetControl', error as Error);
      }
      // Only this run's isolated repository and the returned AssetStore reference are eligible.
      try {
        const cleanup: Repository = new Repository(context, preferencesName, databaseName);
        if (cleanup.state.accounts.some((item: Account) => item.id === account.id)) await cleanup.removeAccount(account.id);
      } catch (error) { failed = true; this.cleanupFailure('RemoveOwnedAccount', error as Error); }
      try { await repository.history.remove(account.id); } catch (error) {
        failed = true; this.cleanupFailure('RemoveOwnedHistory', error as Error);
      }
      try {
        await new Vault().remove(account.secretRef, account.secretParts);
        await this.removedAsset(account.secretRef, account.secretParts);
      } catch (error) { failed = true; this.cleanupFailure('RemoveOwnedAssets', error as Error); }
      try {
        check(JSON.stringify(new Repository(context, preferencesName, databaseName).state) === before);
        check((await repository.history.all()).length === 0);
      } catch (error) { failed = true; this.cleanupFailure('VerifyOwnedDataRemoved', error as Error); }
      if (failed) {
        // A secondary cleanup failure must not replace the initial operation phase.
        if (!operationFailed) this.stage = 'CleanupFixtureAndOwnedData';
        throw new Error('Fixture cleanup failed');
      }
      this.passed.push('FixtureHttpOwnedDataCleanup');
    }
  }
}

/** Run with aa test -s unittest /ets/testrunner/FixtureHttpTestRunner after host fixture and HDC rport setup. */
export default class FixtureHttpTestRunner implements TestRunner {
  onPrepare(): void {}

  async onRun(): Promise<void> {
    const delegator: abilityDelegatorRegistry.AbilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();
    const suite: FixtureHttpSuite = new FixtureHttpSuite();
    let failed: boolean = false;
    try {
      suite.stage = 'GetApplicationContext';
      const context: common.ApplicationContext = delegator.getAppContext().getApplicationContext();
      await suite.run(context);
      // No PASS is printed until every assertion and cleanup has completed successfully.
      for (const name of suite.passed) await delegator.print('PASS ' + name + '\n');
    } catch (error) {
      failed = true;
      try {
        for (const diagnostic of suite.failures) await delegator.print(diagnostic + '\n');
        await delegator.print('FAIL FixtureHttpTestSuite stage=' + suite.stage + ' code=' + failureCode(error as Error) + '\n');
      }
      catch (_) { /* finishTest must still report failure; arbitrary exception details stay private. */ }
    }
    await delegator.finishTest(failed ? 'FAIL FixtureHttpTestSuite' : 'PASS FixtureHttpTestSuite', failed ? 1 : 0);
  }
}
