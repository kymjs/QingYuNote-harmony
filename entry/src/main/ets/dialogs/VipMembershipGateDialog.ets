import { ComponentContent, UIContext } from '@kit.ArkUI'
import { LocaleService } from '../services/LocaleService'

export interface VipMembershipGateDialogParams {
  onClose: () => void
  onSubscribe: () => void
}

@Component
export struct VipMembershipGateDialog {
  @Prop params: VipMembershipGateDialogParams = {
    onClose: (): void => {},
    onSubscribe: (): void => {}
  }

  private loc(zh: string, en: string, ja: string = en): string {
    return LocaleService.loc(zh, en, ja)
  }

  @Builder
  benefitCell(symbol: Resource, title: string, line1: string, line2: string) {
    Column({ space: 4 }) {
      Column() {
        SymbolGlyph(symbol)
          .fontSize(18)
          .fontColor(['#0DAA4A'])
      }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .borderRadius(10)
      .backgroundColor('#E8F8EE')

      Text(title)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor('#222222')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)

      Text(line1)
        .fontSize(10)
        .fontColor('#888888')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)

      Text(line2)
        .fontSize(10)
        .fontColor('#888888')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column() {
          Stack({ alignContent: Alignment.TopStart }) {
            Image($r('app.media.illust_vip_membership_gate_header'))
              .width('100%')
              .height(148)
              .objectFit(ImageFit.Cover)
            Column() {
              Image($r('app.media.icon_app'))
                .width(28)
                .height(28)
                .borderRadius(8)
              Blank()
              Text(this.loc('会员专属功能', 'Member-only features', '会員限定機能'))
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1A1A1A')
              Text(this.loc('开通会员后使用', 'Available after subscribing', '会員登録後に利用'))
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor('#0DAA4A')
                .margin({ top: 2 })
              Text(this.loc('开通会员，解锁全部权益', 'Subscribe to unlock all benefits', '会員ですべての特典を解放'))
                .fontSize(12)
                .fontColor('#2BB673')
                .margin({ top: 4 })
            }
            .width('100%')
            .height(148)
            .padding({ left: 18, right: 18, top: 16, bottom: 12 })
            .alignItems(HorizontalAlign.Start)
            .linearGradient({
              angle: 90,
              colors: [['#EBFFFFFF', 0.0], ['#8CFFFFFF', 0.45], ['#26FFFFFF', 1.0]]
            })
          }
          .width('100%')
          .height(148)

          Column({ space: 14 }) {
            Row({ space: 4 }) {
              this.benefitCell(
                $r('sys.symbol.icloud'),
                this.loc('云端同步', 'Cloud sync', 'クラウド同期'),
                this.loc('50G大空间', '50 GB storage', '50GBの大容量'),
                this.loc('笔记实时同步', 'Realtime note sync', 'ノートをリアルタイム同期')
              )
              this.benefitCell(
                $r('sys.symbol.phone'),
                this.loc('多端访问', 'Multi-device', 'マルチデバイス'),
                this.loc('手机、平板等', 'Phone, tablet & more', 'スマホ・タブレットなど'),
                this.loc('多设备随时查看', 'Access on any device', 'どの端末でも確認')
              )
              this.benefitCell(
                $r('sys.symbol.wand_and_stars'),
                this.loc('AI 辅助', 'AI assist', 'AI支援'),
                this.loc('AI 辅助写作', 'AI writing assist', 'AI執筆支援'),
                this.loc('板书/PPT一键转笔记', 'Slides to notes in one tap', '板書/PPTをワンタップでノートに')
              )
              this.benefitCell(
                $r('sys.symbol.doc_text'),
                this.loc('笔记无上限', 'Unlimited notes', 'ノート無制限'),
                this.loc('创建与存储的笔记', 'Create & store notes', '作成・保存するノート'),
                this.loc('数量无上限', 'No count limit', '件数に上限なし')
              )
            }
            .width('100%')

            Row() {
              SymbolGlyph($r('sys.symbol.star_fill'))
                .fontSize(16)
                .fontColor(['#D4A017'])
                .margin({ right: 6 })
              Column({ space: 2 }) {
                Text(this.loc('限时体验会员', 'Limited-time trial', '期間限定体験会員'))
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#0DAA4A')
                Text(this.loc('低至 ¥0.33 / 天，畅享全部权益', 'From ¥0.33/day, all benefits', '1日約¥0.33から、全特典を利用'))
                  .fontSize(11)
                  .fontColor('#666666')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Text(this.loc('最低 0.33 元/天', 'From ¥0.33/day', '最低 0.33 元/日'))
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor('#E67E22')
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(Color.White)
                .borderRadius(8)
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 10, bottom: 10 })
            .borderRadius(12)
            .linearGradient({
              angle: 90,
              colors: [['#FFF3E0', 0.0], ['#FFE8B8', 1.0]]
            })

            Button(this.loc('立即开通会员', 'Subscribe now', '今すぐ会員になる'))
              .width('100%')
              .height(48)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .backgroundColor('#0DAA4A')
              .borderRadius(24)
              .onClick(() => {
                this.params.onSubscribe()
              })

            Text(this.loc('安全支付 · 隐私保障 · 无自动续费', 'Secure pay · Privacy · No auto-renew',
              '安全決済 · プライバシー保護 · 自動更新なし'))
              .fontSize(11)
              .fontColor('#999999')
              .width('100%')
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 20 })
        }
        .width('100%')
        .backgroundColor(Color.White)
        .borderRadius(20)

        Button({ type: ButtonType.Circle }) {
          Text('×')
            .fontSize(18)
            .fontColor('#999999')
        }
        .width(32)
        .height(32)
        .backgroundColor(Color.Transparent)
        .margin({ top: 6, right: 6 })
        .onClick(() => {
          this.params.onClose()
        })
      }
    }
    .width('86%')
    .constraintSize({ maxWidth: 360 })
    .shadow({
      radius: 24,
      color: '#1F000000',
      offsetX: 0,
      offsetY: 8
    })
  }
}

@Builder
export function buildVipMembershipGateDialogContent(params: VipMembershipGateDialogParams): void {
  VipMembershipGateDialog({ params: params })
}

/**
 * 图一样式会员开通弹窗。
 * @returns true 表示点击「立即开通会员」；false 表示关闭。
 */
export function showVipMembershipGateDialog(uiContext: UIContext): Promise<boolean> {
  return new Promise((resolve) => {
    let holder: ComponentContent<VipMembershipGateDialogParams> | undefined = undefined
    let settled: boolean = false
    const settle = (value: boolean): void => {
      if (settled) {
        return
      }
      settled = true
      resolve(value)
    }
    const closeDialog = (): void => {
      if (holder === undefined) {
        return
      }
      try {
        uiContext.getPromptAction().closeCustomDialog(holder)
      } catch (_) {
        // ignore
      }
    }
    const params: VipMembershipGateDialogParams = {
      onClose: (): void => {
        settle(false)
        closeDialog()
      },
      onSubscribe: (): void => {
        settle(true)
        closeDialog()
      }
    }
    holder = new ComponentContent(uiContext, wrapBuilder(buildVipMembershipGateDialogContent), params)
    try {
      uiContext.getPromptAction().openCustomDialog(holder, {
        alignment: DialogAlignment.Center,
        autoCancel: true,
        onWillDismiss: (action: DismissDialogAction) => {
          if (action.reason === DismissReason.PRESS_BACK ||
            action.reason === DismissReason.TOUCH_OUTSIDE) {
            settle(false)
            action.dismiss()
          }
        }
      })
    } catch (_) {
      settle(false)
    }
  })
}
