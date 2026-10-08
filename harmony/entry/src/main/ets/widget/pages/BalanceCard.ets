const cardStorage: LocalStorage = new LocalStorage();

@Entry(cardStorage)
@Component
struct BalanceCard {
  @LocalStorageProp('total') total: string = '—';
  @LocalStorageProp('status') status: string = '打开应用添加平台';
  @LocalStorageProp('page') page: string = '1/1';
  @LocalStorageProp('name1') name1: string = '暂无平台';
  @LocalStorageProp('value1') value1: string = '—';
  @LocalStorageProp('name2') name2: string = '';
  @LocalStorageProp('value2') value2: string = '';
  @LocalStorageProp('name3') name3: string = '';
  @LocalStorageProp('value3') value3: string = '';
  @LocalStorageProp('name4') name4: string = '';
  @LocalStorageProp('value4') value4: string = '';

  @Builder
  cell(name: string, value: string) {
    Column({ space: 2 }) {
      Text(name).fontSize(11).fontColor('#566D8D').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(value).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#244B91').maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 4 }) {
      Row() {
        Text('API 余额').fontSize(13).fontWeight(FontWeight.Medium).layoutWeight(1)
        Text('刷新').fontSize(12).fontColor('#3469D6').padding(4)
          .onClick(() => postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { refresh: true } }))
      }.width('100%')
      Row() {
        Text(this.total).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#244B91').layoutWeight(1)
        Text(this.page + ' ›').fontSize(12).fontColor('#61738E').padding(4)
          .onClick(() => postCardAction(this, { action: 'message', params: { operation: 'next' } }))
      }.width('100%')
      Row({ space: 12 }) { this.cell(this.name1, this.value1); this.cell(this.name2, this.value2) }.width('100%')
      Row({ space: 12 }) { this.cell(this.name3, this.value3); this.cell(this.name4, this.value4) }.width('100%')
      Text(this.status).fontSize(10).fontColor('#78879B').maxLines(1).width('100%')
    }.padding(12).width('100%').height('100%').backgroundColor('#F1F5FC').borderRadius(20)
  }
}
