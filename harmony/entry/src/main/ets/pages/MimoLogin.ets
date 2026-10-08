import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { Account, Balance } from '../core/Core';
import { Repository } from '../platform/Repository';
import { BalanceService } from '../platform/BalanceService';

class MimoParams { id: string = ''; }

@Entry
@Component
struct MimoLogin {
  @State message: string = '请在小米官方页面登录，完成后点击验证并保存。';
  @State busy: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private repository: Repository | undefined = undefined;
  private account: Account | undefined = undefined;

  aboutToAppear(): void {
    try {
      this.repository = Repository.open(this.getUIContext().getHostContext() as common.UIAbilityContext);
      const params: MimoParams = this.getUIContext().getRouter().getParams() as MimoParams;
      this.account = this.repository.state.accounts.find((a: Account) => a.id === params.id && a.platform === 'mimo');
    } catch (_) { this.message = '账户读取失败，请返回重试'; }
  }

  private async confirmLogin(): Promise<void> {
    if (!this.repository || !this.account || this.busy) return;
    this.busy = true;
    try {
      const cookie: string = webview.WebCookieManager.fetchCookieSync('https://platform.xiaomimimo.com');
      if (!cookie) throw new Error('尚未取得登录会话，请先完成登录');
      const service: BalanceService = new BalanceService(this.repository);
      const balance: Balance = await service.verify(this.account, cookie);
      const copy: Account = JSON.parse(JSON.stringify(this.account)) as Account;
      await this.repository.saveAccount(copy, cookie);
      balance.revision = copy.revision;
      await this.repository.updateBalances([balance]);
      await service.updateCards();
      this.getUIContext().getRouter().back();
    } catch (_) { this.message = '登录会话尚未通过余额接口验证，请完成登录或重新登录后再试'; }
    finally { this.busy = false; }
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 14 }) {
        Button('返回').onClick(() => this.getUIContext().getRouter().back())
        Text('小米 MiMo 登录').fontSize(20).fontWeight(FontWeight.Bold)
      }.width('100%').padding(16)
      Text(this.message).fontSize(13).fontColor('#61738E').padding({ left: 16, right: 16 })
      Web({ src: 'https://platform.xiaomimimo.com/console/balance', controller: this.controller })
        .javaScriptAccess(true).domStorageAccess(true).layoutWeight(1).width('100%')
      Button(this.busy ? '验证中' : '验证并保存会话').enabled(!this.busy)
        .width('90%').height(48).margin({ bottom: 16 }).onClick(() => this.confirmLogin())
    }.width('100%').height('100%').backgroundColor('#F3F6FA')
  }
}
