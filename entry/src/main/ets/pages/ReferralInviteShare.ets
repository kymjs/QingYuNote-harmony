import { pasteboard } from '@kit.BasicServicesKit'

import { AppContextHolder } from '../services/AppContextHolder'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'
import { PageLifecycle } from '../common/utils/PageLifecycle'
import { PreferencesService } from '../services/PreferencesService'
import {
  buildReferralInviteShareText,
  isValidReferralInviterUserId
} from '../common/utils/ReferralInviteNavigation'

const BRAND_GREEN = '#0DAA4A'
const BRAND_LIGHT = '#E8F8EF'
const RULE_TEXT_COLOR = '#2D3748'

@Entry
@Component
struct ReferralInviteShare {
  @State inviterUserId: string = ''
  @State loading: boolean = true
  @State sharing: boolean = false
  private lifecycle = new PageLifecycle()
  private closeGuard = new PageCloseGuard()

  aboutToAppear(): void {
    this.lifecycle.appear()
    this.closeGuard.reset()
    void this.loadInviterUserId()
  }

  aboutToDisappear(): void {
    this.lifecycle.disappear()
  }

  private async loadInviterUserId(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    if (!this.lifecycle.isActive()) {
      return
    }
    const uid = await PreferencesService.getInstance().getNoteApiUserId()
    this.inviterUserId = uid === null ? '' : uid.trim()
    this.loading = false
  }

  private handleToolbarBack(): void {
    this.closeGuard.runBack(() => {
      this.getUIContext().getRouter().back()
    }, 'ReferralInviteShare')
  }

  onBackPress(): boolean {
    this.handleToolbarBack()
    return true
  }

  private showToast(message: string): void {
    if (message.trim().length === 0) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message,
        duration: 2200
      })
    } catch (_) {
    }
  }

  private async shareInviteLink(): Promise<void> {
    if (this.sharing || !isValidReferralInviterUserId(this.inviterUserId)) {
      return
    }
    this.sharing = true
    try {
      const pasteData = pasteboard.createPlainTextData(
        buildReferralInviteShareText(this.inviterUserId)
      )
      const systemPasteboard = pasteboard.getSystemPasteboard()
      await systemPasteboard.setData(pasteData)
      if (!this.lifecycle.isActive()) {
        return
      }
      this.showToast('邀请文案已复制，快去分享给好友吧')
    } catch (err) {
      console.error(`ReferralInviteShare shareInviteLink: ${JSON.stringify(err)}`)
      if (!this.lifecycle.isActive()) {
        return
      }
      this.showToast('复制失败，请长按手动复制链接')
    } finally {
      if (this.lifecycle.isActive()) {
        this.sharing = false
      }
    }
  }

  @Builder
  private buildRuleItem(prefix: string, highlight: string, suffix: string) {
    Text() {
      Span(prefix)
        .fontSize(14)
        .fontColor(RULE_TEXT_COLOR)
        .lineHeight(24)
      Span(highlight)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(RULE_TEXT_COLOR)
        .lineHeight(24)
      Span(suffix)
        .fontSize(14)
        .fontColor(RULE_TEXT_COLOR)
        .lineHeight(24)
    }
    .width('100%')
    .margin({ bottom: 6 })
  }

  @Builder
  private buildPlainRule(text: string) {
    Text(text)
      .fontSize(14)
      .fontColor(RULE_TEXT_COLOR)
      .lineHeight(24)
      .width('100%')
      .margin({ bottom: 6 })
  }

  @Builder
  private buildContentCard() {
    Column() {
      Image($r('app.media.icon_app'))
        .width(72)
        .height(72)
        .objectFit(ImageFit.Contain)
        .margin({ bottom: 16 })

      Text('邀请好友得会员')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ bottom: 8 })

      Text('分享专属邀请链接，好友注册成功后双方均可获得会员奖励')
        .fontSize(15)
        .fontColor($r('app.color.secondary_text'))
        .lineHeight(24)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ bottom: 24 })

      Column() {
        Text('活动规则')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(BRAND_GREEN)
          .width('100%')
          .margin({ bottom: 10 })

        this.buildRuleItem('每成功邀请 1 位好友注册，您得 ', '7 天', '轻羽云会员')
        this.buildRuleItem('好友通过您的链接注册，得 ', '1 个月', '轻羽云会员')
        this.buildPlainRule('仅轻羽云会员可发起邀请，每日最多邀请 5 人')
        this.buildPlainRule('好友须为历史上从未注册过的新用户')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 18, right: 18, top: 16, bottom: 16 })
      .backgroundColor(BRAND_LIGHT)
      .borderRadius(16)
      .margin({ bottom: 24 })

      Button('分享邀请链接')
        .width('100%')
        .height(48)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .backgroundColor(BRAND_GREEN)
        .borderRadius(999)
        .enabled(!this.sharing)
        .opacity(this.sharing ? 0.55 : 1)
        .onClick(() => {
          void this.shareInviteLink()
        })
    }
    .width('100%')
    .padding({ left: 28, right: 28, top: 32, bottom: 28 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(24)
    .border({ width: 1, color: $r('app.color.card_border') })
    .shadow({
      radius: 20,
      color: $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: 4
    })
  }

  @Builder
  private buildMissingState() {
    Text('页面参数无效：缺少邀请人信息。请从 App 设置中的「邀请得会员」进入。')
      .fontSize(15)
      .fontColor($r('app.color.secondary_text'))
      .lineHeight(24)
      .textAlign(TextAlign.Center)
      .width('100%')
      .padding({ left: 8, right: 8, top: 24, bottom: 24 })
  }

  build() {
    Column() {
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(18)
            .fontColor([$r('app.color.primary_text')])
        }
        .height('100%')
        .padding({
          left: $r('app.float.toolbar_icon_button_padding_h'),
          right: $r('app.float.toolbar_icon_button_padding_h')
        })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.pill_radius'))
        .onClick(() => {
          this.handleToolbarBack()
        })

        Row() {
          Text('邀请得会员')
            .fontSize($r('app.float.title_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        .height('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          if (this.loading) {
            Column() {
              LoadingProgress()
                .width(36)
                .height(36)
                .color($r('app.color.accent'))
            }
            .width('100%')
            .height(240)
            .justifyContent(FlexAlign.Center)
          } else if (isValidReferralInviterUserId(this.inviterUserId)) {
            this.buildContentCard()
          } else {
            this.buildMissingState()
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: 520 })
        .padding({ left: 16, right: 16, top: 16, bottom: 32 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 180,
      colors: [['#F0FAF4', 0], ['#FFFFFF', 0.4]]
    })
  }
}
