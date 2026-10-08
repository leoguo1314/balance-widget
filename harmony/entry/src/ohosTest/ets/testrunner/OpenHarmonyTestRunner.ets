import { abilityDelegatorRegistry, TestRunner } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { NativeDeviceSuite, describeNativeFailure } from '../test/NativeDeviceSuite';

/** Real-device tests; no Hypium, mock system Kit, network call, or production Ability startup. */
export default class OpenHarmonyTestRunner implements TestRunner {
  onPrepare(): void {}

  async onRun(): Promise<void> {
    const delegator: abilityDelegatorRegistry.AbilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();
    const suite: NativeDeviceSuite = new NativeDeviceSuite(delegator);
    let failed: number = 0;
    let stage: string = 'Core';
    try {
      failed += await suite.runCore();
      stage = 'GetAppContext';
      const delegatorContext: common.Context = delegator.getAppContext();
      const present: boolean = delegatorContext !== undefined && delegatorContext !== null;
      await delegator.print('DIAG DelegatorContext present=' + present + ' stageMode=' +
        (present && delegatorContext.stageMode === true) + '\n');
      if (!present) throw new Error('Native context unavailable');
      stage = 'GetApplicationContext';
      // Delegator returns a raw base context; ArkData requires the Stage-model wrapper.
      // The official Context API obtains that wrapper without starting the production Ability.
      const appContext: common.ApplicationContext = delegatorContext.getApplicationContext();
      stage = 'Storage';
      // Module contexts are for module resources; directory differences are not an isolation contract.
      // Each storage case supplies explicit UUID-only Preferences/database names instead.
      failed += await suite.runStorage(appContext);
    } catch (error) {
      failed++;
      try { await delegator.print('FAIL NativeRunner stage=' + stage + describeNativeFailure(error as Error) + '\n'); }
      catch (_) { /* finishTest still reports failure; never print arbitrary exception text. */ }
    }
    await delegator.finishTest(failed === 0 ? 'PASS NativeDeviceSuite' : 'FAIL NativeDeviceSuite', failed === 0 ? 0 : 1);
  }
}
