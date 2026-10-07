import { abilityDelegatorRegistry, TestRunner } from '@kit.TestKit';
import { application, common } from '@kit.AbilityKit';
import { NativeDeviceSuite } from '../test/NativeDeviceSuite';

/** Real-device tests; no Hypium, mock system Kit, network call, or production Ability startup. */
export default class OpenHarmonyTestRunner implements TestRunner {
  onPrepare(): void {}

  async onRun(): Promise<void> {
    const delegator: abilityDelegatorRegistry.AbilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();
    const suite: NativeDeviceSuite = new NativeDeviceSuite(delegator);
    let failed: number = 0;
    try {
      failed += await suite.runCore();
      const appContext: common.Context = delegator.getAppContext();
      const testContext: common.Context = await application.createModuleContext(appContext, 'entry_test');
      const mainContext: common.Context = await application.createModuleContext(appContext, 'entry');
      // HistoryStore.record performs retention cleanup and Repository.save writes its whole state.
      // Never invoke them against the installed application's production directories.
      if (!testContext.databaseDir || !testContext.preferencesDir ||
        testContext.databaseDir === mainContext.databaseDir ||
        testContext.preferencesDir === mainContext.preferencesDir) {
        failed++;
        await delegator.print('FAIL StorageIsolation\n');
      } else {
        await delegator.print('PASS StorageIsolation\n');
        failed += await suite.runStorage(testContext);
      }
    } catch (_) {
      failed++;
      try { await delegator.print('FAIL NativeRunner\n'); } catch (_) { /* finishTest still reports failure. */ }
    }
    await delegator.finishTest(failed === 0 ? 'PASS NativeDeviceSuite' : 'FAIL NativeDeviceSuite', failed === 0 ? 0 : 1);
  }
}
