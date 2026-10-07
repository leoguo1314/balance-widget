import { UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want): void {
    AppStorage.setOrCreate('foreground', true);
    AppStorage.setOrCreate('refreshSerial', want.parameters?.refresh ? Date.now() : 0);
  }
  onWindowStageCreate(stage: window.WindowStage): void {
    stage.loadContent('pages/Index');
  }
  onNewWant(want: Want): void {
    if (want.parameters?.refresh) AppStorage.setOrCreate('refreshSerial', Date.now());
  }
  onForeground(): void { AppStorage.setOrCreate('foreground', true); }
  onBackground(): void { AppStorage.setOrCreate('foreground', false); }
}
