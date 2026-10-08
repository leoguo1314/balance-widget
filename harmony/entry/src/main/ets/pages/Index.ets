import { common } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { Account, Balance, Snapshot, Summary, Usage, summarize, amount, usageOf } from '../core/Core';
import { Repository } from '../platform/Repository';
import { BalanceService } from '../platform/BalanceService';
import { HistoryChart } from '../components/HistoryChart';

@Entry
@Component
struct Index {
  @State accounts: Account[] = [];
  @State balances: Balance[] = [];
  @State history: Snapshot[] = [];
  @State busy: boolean = false;
  @State message: string = '';
  @State rate: string = '7.2';
  @State interval: string = '5';
  @State selected: string = '';
  @State days: number = 7;
  @StorageLink('foreground') @Watch('visibilityChanged') foreground: boolean = true;
  @StorageLink('refreshSerial') @Watch('refreshRequested') refreshSerial: number = 0;
  private repository: Repository | undefined = undefined;
  private service: BalanceService | undefined = undefined;
  private timer: number = -1;
  private pageVisible: boolean = false;
  private activeTab: number = 0;

  aboutToAppear(): void { this.load(); }
  onPageShow(): void { this.pageVisible = true; this.load(); this.refresh(); }
  onPageHide(): void { this.pageVisible = false; this.stopTimer(); }
  aboutToDisappear(): void { this.pageVisible = false; this.stopTimer(); }

  private load(): void {
    try {
      this.repository = Repository.open(this.getUIContext().getHostContext() as common.UIAbilityContext);
      this.service = new BalanceService(this.repository);
      this.syncState(); this.startTimer();
      this.repository.history.all().then((points: Snapshot[]) => { this.history = points; })
        .catch(() => { this.message = '历史记录读取失败，请重试'; });
      if (!this.selected && this.accounts.length > 0) this.selected = this.accounts[0].id;
      if (this.pageVisible && this.refreshSerial > 0) { AppStorage.setOrCreate('refreshSerial', 0); this.refresh(); }
    } catch (_) { this.message = '本地数据加载失败，请保留数据并重启应用'; }
  }

  private syncState(readSettings: boolean = true): void {
    if (!this.repository) return;
    this.accounts = this.repository.state.accounts.slice();
    this.balances = this.repository.state.balances.slice();
    if (readSettings) {
      this.rate = String(this.repository.state.settings.usdCny);
      this.interval = String(this.repository.state.settings.refreshMinutes);
    }
  }

  private stopTimer(): void { if (this.timer >= 0) clearInterval(this.timer); this.timer = -1; }
  private startTimer(): void {
    this.stopTimer();
    if (!this.foreground || !this.pageVisible || !this.repository) return;
    this.timer = setInterval(() => this.refresh(), this.repository.state.settings.refreshMinutes * 60000);
  }
  visibilityChanged(): void {
    if (this.foreground && this.pageVisible) { this.startTimer(); this.refresh(); }
    else this.stopTimer();
  }
  refreshRequested(): void {
    if (this.pageVisible && this.foreground && this.service && this.refreshSerial > 0) {
      AppStorage.setOrCreate('refreshSerial', 0); this.refresh();
    }
  }

  private async refresh(): Promise<void> {
    if (this.busy || !this.foreground || !this.pageVisible || !this.service || !this.repository) return;
    this.busy = true; this.message = '';
    try {
      await this.service.refresh(); this.syncState(false);
      this.history = await this.repository.history.all();
    } catch (_) { this.message = '刷新未完成，请重试；原有余额保留'; }
    finally { this.busy = false; }
  }

  private total(): Summary {
    return summarize(this.accounts, this.balances, this.repository?.state.settings.usdCny || 7.2);
  }
  private balanceOf(id: string): Balance | undefined {
    const account: Account | undefined = this.accounts.find((a: Account) => a.id === id);
    return this.balances.find((b: Balance) => b.accountId === id && b.revision === account?.revision);
  }
  private display(id: string): string {
    if (this.accounts.some((a: Account) => a.id === id && a.platform === 'modelscope')) return '免费服务';
    const b: Balance | undefined = this.balanceOf(id);
    return b && b.hasValue ? amount(b.value, b.currency) : '待查询';
  }
  private status(id: string): string {
    const b: Balance | undefined = this.balanceOf(id);
    if (!b) return '尚未查询';
    return (b.stale ? '缓存 · ' : '') + (b.error || ('更新于 ' + new Date(b.updatedAt).toLocaleString()));
  }
  private points(): Snapshot[] {
    const account: Account | undefined = this.accounts.find((a: Account) => a.id === this.selected);
    return this.history.filter((p: Snapshot) => p.accountId === this.selected && p.revision === account?.revision &&
      p.timestamp >= Date.now() - this.days * 86400000);
  }
  private usage(id: string): Usage {
    const account: Account | undefined = this.accounts.find((a: Account) => a.id === id);
    return usageOf(this.history.filter((p: Snapshot) => p.revision === account?.revision), id, Date.now() - this.days * 86400000);
  }
  private edit(id: string = ''): void { this.getUIContext().getRouter().pushUrl({ url: 'pages/EditAccount', params: { id: id } }); }

  private remove(account: Account): void {
    this.getUIContext().showAlertDialog({
      title: '删除 ' + account.label + '？', message: '会删除该凭证及其本地历史记录。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', fontColor: '#C63B43', action: () => {
        this.repository?.removeAccount(account.id).then(() => {
          this.syncState(); this.service?.updateCards();
        }).catch(() => { this.message = '删除未完成，请重试'; });
      } }
    });
  }

  private async saveSettings(): Promise<void> {
    if (!this.repository) return;
    const rate: number = Number(this.rate); const interval: number = Number(this.interval);
    if (!Number.isFinite(rate) || rate <= 0 || rate > 100) { this.message = '请输入有效折算率'; return; }
    if (!Number.isInteger(interval) || interval < 2 || interval > 360) { this.message = '前台刷新间隔应为 2–360 分钟'; return; }
    try {
      this.repository.state.settings.usdCny = rate;
      this.repository.state.settings.refreshMinutes = interval;
      await this.repository.save(); this.startTimer(); await this.service?.updateCards();
      this.message = '设置已保存';
    } catch (_) { this.message = '设置保存失败'; }
  }

  private async notifications(): Promise<void> {
    if (!this.repository) return;
    try {
      await notificationManager.requestEnableNotification(this.getUIContext().getHostContext() as common.UIAbilityContext);
      this.repository.state.settings.notifications = await notificationManager.isNotificationEnabled();
      await this.repository.save();
      this.message = this.repository.state.settings.notifications ? '余额提醒已开启' : '通知未获授权';
    } catch (_) { this.message = '通知未获授权，可在系统设置中允许后重试'; }
  }

  private async exportHistory(): Promise<void> {
    if (!this.repository) return;
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(this.getUIContext().getHostContext() as common.UIAbilityContext);
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      const today: Date = new Date();
      const date: string = today.getFullYear() + '-' + String(today.getMonth() + 1).padStart(2, '0') + '-' +
        String(today.getDate()).padStart(2, '0');
      options.newFileNames = ['API余额统计-' + date + '.json'];
      const uris: string[] = await documentPicker.save(options);
      if (uris.length === 0) return;
      const report: string = await this.repository.exportReport();
      const file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(file.fd, report); } finally { fileIo.closeSync(file); }
      this.message = '统计已导出，不包含 API Key 或登录会话';
    } catch (_) { this.message = '导出未完成，请重新选择文件位置'; }
  }

  @Builder
  accountCard(account: Account) {
    Column({ space: 10 }) {
      Row() {
        Text(account.label).fontSize(17).fontWeight(FontWeight.Medium).layoutWeight(1)
        Text(account.enabled ? '' : '已停用').fontSize(12).fontColor('#78879B')
      }.width('100%')
      Text(this.display(account.id)).fontSize(28).fontWeight(FontWeight.Bold).fontColor('#244B91').width('100%')
      Text(this.status(account.id)).fontSize(12).fontColor('#78879B').width('100%')
      if (account.platform === 'qiniu') { Text('本月消费，非账户余额').fontSize(12).fontColor('#78879B').width('100%') }
      Row({ space: 14 }) {
        Button('编辑').onClick(() => this.edit(account.id))
        if (account.platform === 'mimo') {
          Button('小米登录').onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/MimoLogin', params: { id: account.id } }))
        }
        Button('删除').fontColor('#C63B43').backgroundColor('#FCEEEF').onClick(() => this.remove(account))
      }.width('100%')
    }.padding(20).backgroundColor(Color.White).borderRadius(20).width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('API 余额').fontSize(26).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button(this.busy ? '查询中' : '刷新').enabled(!this.busy).onClick(() => this.refresh())
      }.width('100%').padding({ left: 20, right: 20, top: 12 })
      if (this.message) { Text(this.message).fontSize(13).fontColor('#6C7290').padding({ left: 20, right: 20 }).width('100%') }
      Tabs({ barPosition: BarPosition.End }) {
        TabContent() {
          Scroll() {
            Column({ space: 16 }) {
              Column({ space: 8 }) {
                Text('余额汇总 · 人民币').fontSize(14).fontColor('#61738E')
                Text(this.total().values > 0 ? amount(this.total().cny, 'CNY') : '—').fontSize(40).fontWeight(FontWeight.Bold).fontColor('#244B91')
                Text(this.total().cached + ' 项缓存 · ' + this.total().missing + ' 项待查询').fontSize(12).fontColor('#61738E')
                Text('美元按设置中的折算率估算：' + (this.repository?.state.settings.usdCny || 7.2)).fontSize(11).fontColor('#8491A4')
              }.padding(24).backgroundColor('#E6EFFD').borderRadius(24).width('100%')
              ForEach(this.accounts, (account: Account) => { this.accountCard(account) }, (account: Account) => account.id)
              Button('添加平台 / Key').width('100%').height(48).onClick(() => this.edit())
              Text('同账户的多个 Key 可填写相同账户组；不同账户保持独立。').fontSize(12).fontColor('#78879B')
            }.padding(20).width('100%')
          }.width('100%').height('100%')
        }.tabBar('余额')
        TabContent() {
          Scroll() {
            Column({ space: 16 }) {
              Text('余额历史').fontSize(22).fontWeight(FontWeight.Bold).width('100%')
              Select(this.accounts.map((a: Account): SelectOption => ({ value: a.label }))).value('选择账户')
                .onSelect((index: number) => { this.selected = this.accounts[index].id; })
              Select([{ value: '7 天' }, { value: '30 天' }, { value: '90 天' }, { value: '180 天' }])
                .selected(0).value(this.days + ' 天').onSelect((index: number) => { this.days = [7, 30, 90, 180][index]; })
              HistoryChart({ points: this.points() })
              Text(this.points().length === 0 ? '查询成功后开始积累历史记录' : '历史记录 ' + this.points().length + ' 个采样点')
                .fontSize(12).fontColor('#78879B')
              ForEach(this.accounts, (a: Account) => {
                Column({ space: 6 }) {
                  Text(a.label).fontSize(16).fontWeight(FontWeight.Medium)
                  if (a.platform === 'qiniu') {
                    Text('本月累计消费见余额页；此项不使用余额差值估计消耗。').fontSize(13).fontColor('#78879B')
                  } else if (a.platform === 'modelscope') {
                    Text('免费平台，无余额统计。').fontSize(13).fontColor('#78879B')
                  } else {
                    Text('消耗估计 ' + amount(this.usage(a.id).consumed, this.balanceOf(a.id)?.currency || a.currency)).fontSize(14)
                    Text('余额增加 ' + amount(this.usage(a.id).increases, this.balanceOf(a.id)?.currency || a.currency)).fontSize(14).fontColor('#78879B')
                  }
                }.padding(16).backgroundColor(Color.White).borderRadius(16).width('100%').alignItems(HorizontalAlign.Start)
              }, (a: Account) => a.id)
              Text('统计来自余额快照差值；余额增加可能是充值或退款，不代表请求级账单。').fontSize(12).fontColor('#78879B')
            }.width('100%').padding(20)
          }.width('100%').height('100%')
        }.tabBar('统计')
        TabContent() {
          Scroll() {
            Column({ space: 16 }) {
              Text('刷新与折算').fontSize(22).fontWeight(FontWeight.Bold).width('100%')
              Text('打开应用、返回前台和切换导航时自动刷新；停留页面时按下方间隔定时刷新，也可随时手动刷新。').fontSize(13).fontColor('#61738E')
              Text('前台自动刷新间隔（分钟，可选调整）').width('100%').fontSize(14)
              TextInput({ text: this.interval }).id('foreground-refresh-minutes').type(InputType.Number).onChange((value: string) => { this.interval = value; })
              Text('美元折算人民币（手动设置）').width('100%').fontSize(14)
              TextInput({ text: this.rate }).id('usd-cny-rate').type(InputType.NUMBER_DECIMAL).onChange((value: string) => { this.rate = value; })
              Button('保存设置').id('save-refresh-settings').width('100%').onClick(() => this.saveSettings())
              Button('开启低余额通知').width('100%').onClick(() => this.notifications())
              Button('导出统计与配置').width('100%').onClick(() => this.exportHistory())
              Text('桌面服务卡片').fontSize(22).fontWeight(FontWeight.Bold).width('100%')
              Text('长按桌面应用图标 → 服务卡片 → API 余额 → 添加到桌面。卡片显示 4 个平台，点击翻页读取缓存，点击刷新打开应用查询。').fontSize(14).fontColor('#61738E')
              Text('卡片定时更新由系统调度；应用退出后不承诺精确分钟级刷新。').fontSize(12).fontColor('#78879B')
              Text('数据与隐私').fontSize(22).fontWeight(FontWeight.Bold).width('100%')
              Text('API Key 与登录会话保存在鸿蒙安全资产库；余额和历史保存在本机。导出文件不含凭证，换手机需重新输入 Key。').fontSize(14).fontColor('#61738E')
              Text('Android 的 mihomo 内核与全局 VPN 尚未移植。本版使用系统已有网络连接。').fontSize(12).fontColor('#78879B')
              Text('BalanceWidget 鸿蒙版 · AGPL-3.0').fontSize(12).fontColor('#78879B')
            }.width('100%').padding(20)
          }.width('100%').height('100%')
        }.tabBar('设置')
      }.layoutWeight(1).width('100%')
        .onChange((index: number) => { this.activeTab = index; this.refresh(); })
        .onTabBarClick((index: number) => { if (index === this.activeTab) this.refresh(); })
    }.width('100%').height('100%').backgroundColor('#F3F6FA')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
