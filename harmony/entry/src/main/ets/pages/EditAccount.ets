import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { Account, PRESETS, Preset, newAccount, presetFor } from '../core/Core';
import { Repository } from '../platform/Repository';
import { BalanceService } from '../platform/BalanceService';
import { AliyunCredential } from '../platform/NetClient';

class RouteParams { id: string = ''; }

@Entry
@Component
struct EditAccount {
  @State account: Account = new Account();
  @State credential: string = '';
  @State aliyunSecret: string = '';
  @State threshold: string = '10';
  @State presetIndex: number = 0;
  @State message: string = '';
  @State saving: boolean = false;
  private repository: Repository | undefined = undefined;

  aboutToAppear(): void {
    try {
      this.repository = Repository.open(this.getUIContext().getHostContext() as common.UIAbilityContext);
      const params: RouteParams = this.getUIContext().getRouter().getParams() as RouteParams;
      const existing: Account | undefined = this.repository.state.accounts.find((a: Account) => a.id === params?.id);
      this.account = existing ? JSON.parse(JSON.stringify(existing)) as Account : newAccount(util.generateRandomUUID(), 'deepseek');
      this.presetIndex = PRESETS.findIndex((p: Preset) => p.id === this.account.platform);
      this.threshold = String(this.account.threshold);
    } catch (_) { this.message = '配置加载失败，请返回重试'; }
  }

  private switchPreset(index: number): void {
    const id: string = this.account.id;
    this.account = newAccount(id, PRESETS[index].id);
    this.presetIndex = index; this.credential = ''; this.aliyunSecret = '';
    this.threshold = String(this.account.threshold);
  }

  private syncAccount(): void { this.account = JSON.parse(JSON.stringify(this.account)) as Account; }

  private async save(): Promise<void> {
    if (!this.repository || this.saving) return;
    this.saving = true; this.message = '';
    try {
      this.account.threshold = Number(this.threshold);
      let credential: string = this.credential.trim();
      if (this.account.platform === 'dashscope' && (credential || this.aliyunSecret)) {
        if (!credential || !this.aliyunSecret.trim()) throw new Error('请同时填写 AccessKeyId 与 AccessKeySecret');
        const key: AliyunCredential = new AliyunCredential(); key.id = credential; key.secret = this.aliyunSecret.trim();
        credential = JSON.stringify(key);
      }
      await this.repository.saveAccount(this.account, credential);
      this.credential = ''; this.aliyunSecret = '';
      await new BalanceService(this.repository).updateCards();
      this.getUIContext().getRouter().back();
    } catch (error) { this.message = error instanceof Error ? error.message : '保存失败，请重试'; }
    finally { this.saving = false; }
  }

  build() {
    Column() {
      Row({ space: 16 }) {
        Button('返回').onClick(() => this.getUIContext().getRouter().back())
        Text('平台与凭证').fontSize(24).fontWeight(FontWeight.Bold)
      }.padding(20).width('100%')
      Scroll() {
        Column({ space: 14 }) {
          Text('选择平台').fontSize(14).width('100%')
          Select(PRESETS.map((p: Preset): SelectOption => ({ value: p.name }))).selected(this.presetIndex).value(PRESETS[this.presetIndex].name)
            .onSelect((index: number) => this.switchPreset(index))
          Text(presetFor(this.account.platform).note).fontSize(12).fontColor('#78879B').width('100%')
          TextInput({ text: this.account.label, placeholder: '名称，例如主力项目' }).onChange((v: string) => { this.account.label = v; })
          TextInput({ text: this.account.group, placeholder: '账户组：同账户多 Key 填同组；不同账户留空' }).onChange((v: string) => { this.account.group = v; })
          if (this.account.platform !== 'modelscope') {
            Text('余额查询地址').fontSize(14).width('100%')
            TextInput({ text: this.account.endpoint, placeholder: 'https://example.com/balance' })
              .enabled(this.account.platform === 'custom' || this.account.platform === 'workbuddy')
              .onChange((v: string) => { this.account.endpoint = v.trim(); })
          }
          if (this.account.platform !== 'mimo' && this.account.platform !== 'modelscope') {
            Text(this.account.platform === 'dashscope' ? 'AccessKeyId' : 'API Key').fontSize(14).width('100%')
            TextInput({ text: this.credential, placeholder: this.account.secretRef ? '留空保留原凭证' : '输入凭证' })
              .type(InputType.Password).onChange((v: string) => { this.credential = v; })
            if (this.account.platform === 'dashscope') {
              TextInput({ text: this.aliyunSecret, placeholder: 'AccessKeySecret；留空保留原凭证' })
                .type(InputType.Password).onChange((v: string) => { this.aliyunSecret = v; })
            }
          }
          if (this.account.platform === 'custom') {
            TextInput({ text: this.account.path, placeholder: 'JSON 路径，例如 data.balance 或 accounts[0].balance' })
              .onChange((v: string) => { this.account.path = v; })
            Select([{ value: 'GET' }, { value: 'POST（空 JSON 请求体）' }]).value(this.account.method)
              .onSelect((index: number) => { this.account.method = index === 0 ? 'GET' : 'POST'; })
          }
          if (this.account.platform === 'custom') {
            Select([{ value: '人民币 CNY' }, { value: '美元 USD' }, { value: '积分 POINT' }]).value(this.account.currency)
              .onSelect((index: number) => { this.account.currency = ['CNY', 'USD', 'POINT'][index]; this.syncAccount(); })
          } else if (this.account.platform === 'deepseek') {
            Select([{ value: '人民币 CNY' }, { value: '美元 USD' }]).value(this.account.currency)
              .onSelect((index: number) => { this.account.currency = ['CNY', 'USD'][index]; this.syncAccount(); })
          } else { Text('币种：' + this.account.currency).fontSize(13).fontColor('#78879B').width('100%') }
          TextInput({ text: this.threshold, placeholder: '低余额提醒阈值（原币种）' }).type(InputType.Number)
            .onChange((v: string) => { this.threshold = v; })
          Row() {
            Text('启用查询').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.account.enabled }).onChange((v: boolean) => { this.account.enabled = v; })
          }.width('100%')
          if (['qiniu', 'modelscope', 'workbuddy'].indexOf(this.account.platform) < 0 && this.account.currency !== 'POINT') {
            Row() {
              Text('计入余额汇总').layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.account.includeInTotal }).onChange((v: boolean) => { this.account.includeInTotal = v; })
            }.width('100%')
          }
          if (this.account.platform === 'custom' || this.account.platform === 'workbuddy') {
            Row() {
              Text('允许此地址用 HTTP 传输 Key').fontSize(13).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.account.allowHttp }).onChange((v: boolean) => { this.account.allowHttp = v; })
            }.width('100%')
          }
          if (this.account.platform === 'mimo') { Text('先保存平台，然后在余额页点击“小米登录”。').fontSize(13).fontColor('#78879B') }
          if (this.message) { Text(this.message).fontSize(13).fontColor('#C63B43').width('100%') }
          Button(this.saving ? '保存中' : '保存').width('100%').height(48).enabled(!this.saving).onClick(() => this.save())
        }.padding(20).width('100%')
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor('#F3F6FA')
  }
}
