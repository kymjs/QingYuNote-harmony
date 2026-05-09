import promptAction from '@ohos.promptAction'
import type common from '@ohos.app.ability.common'
import { Want } from '@kit.AbilityKit'
import * as wxopensdk from '@tencent/wechat_open_sdk'
import { AppContextHolder } from '../services/AppContextHolder'
import { NoteApiClient } from '../services/NoteApiClient'
import { PreferencesService } from '../services/PreferencesService'
import {
  startWeChatAppPay,
  WECHAT_PAY_RESULT_EVENT,
  type WeChatPayResultPayload
} from '../services/WeChatAuthService'
import type { QingyuRechargePlanId } from '../common/constants/QingyuRechargePlans'
import { QingyuRechargePlans } from '../common/constants/QingyuRechargePlans'
import { Logger } from '../common/utils/Logger'

function delayMs(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms)
  })
}

/**
 * 轻羽云服务 — 会员档位与微信支付入口。
 * 这个页面也叫会员充值页面。
 */
@Entry
@Component
struct QingyuCloudRecharge {
  @State selectedPlan: QingyuRechargePlanId = 'monthly'
  @State applying: boolean = false

  aboutToAppear(): void {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      void PreferencesService.getInstance().init(context)
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message,
        duration: 2500
      })
    } catch (_) {
      console.error('QingyuCloudRecharge showToast failed')
    }
  }

  private openServiceAgreement(): void {
    const context = AppContextHolder.tryGetContext()
    if (context === undefined) {
      return
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: 'https://note.kymjs.com/private/terms.html'
    }
    context.startAbility(want).catch((err: Error) => {
      console.error(`openServiceAgreement: ${JSON.stringify(err)}`)
    })
  }

  /** 微信支付：服务端下单 → 调起微信 APP → 回调后轮询订单直至支付成功。 */
  private async onWeChatPay(): Promise<void> {
    await this.runConfirmedPurchase()
  }

  private async waitForPayPayload(timeoutMs: number): Promise<WeChatPayResultPayload> {
    return await new Promise<WeChatPayResultPayload>((resolve, reject) => {
      const hub = AppContextHolder.getContext().eventHub
      let timerId: number = -1
      const handler = (payload: Object): void => {
        hub.off(WECHAT_PAY_RESULT_EVENT, handler)
        if (timerId >= 0) {
          clearTimeout(timerId)
        }
        resolve(payload as WeChatPayResultPayload)
      }
      hub.on(WECHAT_PAY_RESULT_EVENT, handler)
      timerId = setTimeout((): void => {
        hub.off(WECHAT_PAY_RESULT_EVENT, handler)
        reject(new Error('支付结果超时'))
      }, timeoutMs)
    })
  }

  private async pollOrderUntilPaid(orderId: number): Promise<boolean> {
    for (let i = 0; i < 45; i++) {
      await delayMs(2000)
      const o = await NoteApiClient.getInstance().getOrder(orderId)
      if (o !== null && o.status === 'paid') {
        return true
      }
    }
    return false
  }

  private async runConfirmedPurchase(): Promise<void> {
    if (this.applying) {
      return
    }
    const preview = await PreferencesService.getInstance().getQingyuCloudConfigPreview()
    if (preview === null || !preview.enabled) {
      this.showToast('请先使用微信登录并完成服务端绑定后再充值')
      return
    }
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      this.showToast('请先使用微信登录以开通支付')
      return
    }
    const plan = this.selectedPlan
    const yuan = QingyuRechargePlans.priceYuan(plan)
    const planTitle = QingyuRechargePlans.title(plan)
    const channelLabel = '微信支付'
    const prompt = this.getUIContext().getPromptAction()
    const dialogOpts: promptAction.ShowDialogOptions = {
      title: `${channelLabel}`,
      message: `确认购买「${planTitle}」¥${yuan}？支付成功后将为您的账号延长轻羽云服务有效期（按档位顺延）。`,
      buttons: [
        { text: '取消', color: '#6B7280' },
        { text: '确认支付', color: '#0DAA4A' }
      ]
    }
    try {
      const result: promptAction.ShowDialogSuccessResponse = await prompt.showDialog(dialogOpts)
      if (result.index !== 1) {
        return
      }
    } catch (error) {
      Logger.warn('QingyuCloudRecharge', `showDialog failed: ${JSON.stringify(error)}`)
      return
    }

    this.applying = true
    try {
      const created = await NoteApiClient.getInstance().createOrder(plan)
      if (created === null || created.id === undefined || created.id <= 0) {
        this.showToast('创建订单失败，请稍后重试')
        return
      }
      const prepay = await NoteApiClient.getInstance().wechatPrepay(created.id)
      if (prepay === null) {
        this.showToast('暂无法拉起微信支付（服务端商户参数未就绪）')
        return
      }
      const pid = prepay.prepay_id?.trim() ?? ''
      if (pid.length === 0) {
        this.showToast('获取支付参数失败')
        return
      }
      const host = this.getUIContext().getHostContext()
      const ctx = host as common.UIAbilityContext
      const req = new wxopensdk.PayReq()
      req.appId = prepay.app_id ?? ''
      req.partnerId = prepay.partner_id ?? ''
      req.prepayId = pid
      req.packageValue = prepay.package ?? 'Sign=WXPay'
      req.nonceStr = prepay.nonce_str ?? ''
      req.timeStamp = prepay.timestamp ?? ''
      req.sign = prepay.sign ?? ''
      req.signType = prepay.sign_type ?? 'RSA'
      const sent = await startWeChatAppPay(ctx, req)
      if (!sent) {
        this.showToast('无法拉起微信支付')
        return
      }
      let payResult: WeChatPayResultPayload
      try {
        payResult = await this.waitForPayPayload(120000)
      } catch (error) {
        Logger.warn('QingyuCloudRecharge', `wait pay: ${JSON.stringify(error)}`)
        this.showToast('未收到支付结果，请稍后在会员页刷新')
        return
      }
      if (payResult.errCode !== wxopensdk.ErrCode.ERR_OK) {
        if (payResult.errCode === wxopensdk.ErrCode.ERR_USER_CANCEL) {
          this.showToast('已取消支付')
        } else {
          this.showToast(payResult.errStr ?? '支付未完成')
        }
        return
      }
      const ok = await this.pollOrderUntilPaid(created.id)
      if (!ok) {
        this.showToast('支付确认中，请稍后下拉刷新会员状态')
        return
      }
      const sub = await NoteApiClient.getInstance().fetchSubscription()
      const ymd = sub?.expires_at?.trim() ?? ''
      if (ymd.length > 0) {
        this.showToast(`支付成功，云服务有效期已更新至 ${ymd}`)
      } else {
        this.showToast('支付成功')
      }
    } catch (error) {
      Logger.warn('QingyuCloudRecharge', `purchase: ${JSON.stringify(error)}`)
      const msg = error instanceof Error ? error.message : `${error}`
      this.showToast(msg.length > 0 ? msg : '充值失败，请稍后重试')
    } finally {
      this.applying = false
    }
  }

  @Builder
  private buildPlanCard(planId: QingyuRechargePlanId) {
    Column({ space: 8 }) {
      Text(QingyuRechargePlans.cardHeadline(planId))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.qingyu_member_plan_text'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
      Text(QingyuRechargePlans.cardTagline(planId))
        .fontSize(11)
        .fontColor($r('app.color.qingyu_member_plan_subtext'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({
      left: 10,
      right: 10,
      top: 14,
      bottom: 14
    })
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.selectedPlan === planId ? $r('app.color.qingyu_member_plan_bg_pressed') :
      $r('app.color.qingyu_member_plan_bg'))
    .borderRadius(14)
    .border({
      width: this.selectedPlan === planId ? 2 : 0,
      color: $r('app.color.accent')
    })
    .shadow({
      radius: this.selectedPlan === planId ? 16 : 8,
      color: $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: 4
    })
    .onClick(() => {
      this.selectedPlan = planId
    })
  }

  @Builder
  private buildPrivilegeGlyph(glyph: string) {
    Column() {
      Text(glyph)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.accent'))
    }
    .width(44)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.accent_subtle'))
    .borderRadius(12)
  }

  @Builder
  private buildPrivilegeRow(glyph: string, title: Resource, desc: Resource) {
    Row({ space: 14 }) {
      this.buildPrivilegeGlyph(glyph)
      Column({ space: 6 }) {
        Text(title)
          .fontSize($r('app.float.body_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .width('100%')
        Text(desc)
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
          .lineHeight(18)
      }
      .layoutWeight(1)
      .constraintSize({ minWidth: 0 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private buildPrivilegeSectionDivider() {
    Row() {
      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'))
        .layoutWeight(1)
      Text($r('app.string.qingyu_privilege_section_title'))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.tertiary_text'))
        .margin({ left: 14, right: 14 })
      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'))
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: 8, bottom: 8 })
  }

  build() {
    Column() {
      Row() {
        Row() {
          Image($r('app.media.ic_back'))
            .width($r('app.float.toolbar_back_icon_size'))
            .height($r('app.float.toolbar_back_icon_size'))
            .objectFit(ImageFit.Contain)
        }
        .width(48)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.getUIContext().getRouter().back()
        })

        Column({ space: 4 }) {
          Text($r('app.string.settings_qingyu_title'))
            .fontSize($r('app.float.title_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .textAlign(TextAlign.Start)
            .width('100%')
          Text($r('app.string.qingyu_recharge_tagline'))
            .fontSize(12)
            .fontColor($r('app.color.tertiary_text'))
            .textAlign(TextAlign.Start)
            .width('100%')
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
        .padding({ right: 16 })
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .padding({ left: 4, right: 4 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 0 }) {
          Row({ space: 8 }) {
            this.buildPlanCard('monthly')
            this.buildPlanCard('half_year')
            this.buildPlanCard('yearly')
          }
          .width('100%')
          .padding({ top: 8 })

          Column({ space: 0 }) {
            this.buildPrivilegeSectionDivider()

            this.buildPrivilegeRow('云', $r('app.string.qingyu_privilege_sync_title'),
              $r('app.string.qingyu_privilege_sync_desc'))
            Divider().color($r('app.color.divider')).strokeWidth(1).margin({ left: 58 })

            this.buildPrivilegeRow('端', $r('app.string.qingyu_privilege_multi_title'),
              $r('app.string.qingyu_privilege_multi_desc'))
            Divider().color($r('app.color.divider')).strokeWidth(1).margin({ left: 58 })

            this.buildPrivilegeRow('图', $r('app.string.qingyu_privilege_media_title'),
              $r('app.string.qingyu_privilege_media_desc'))
            Divider().color($r('app.color.divider')).strokeWidth(1).margin({ left: 58 })

            this.buildPrivilegeRow('免', $r('app.string.qingyu_privilege_safe_title'),
              $r('app.string.qingyu_privilege_safe_desc'))
          }
          .width('100%')
          .constraintSize({ minWidth: 0 })
          .padding({
            left: 16,
            right: 16,
            top: 8,
            bottom: 12
          })
          .margin({ top: 12 })
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({ width: 1, color: $r('app.color.card_border') })
          .shadow({
            radius: 20,
            color: $r('app.color.shadow_color'),
            offsetX: 0,
            offsetY: 4
          })

          Text('支付方式')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.tertiary_text'))
            .width('100%')
            .margin({ left: 4, top: 20, bottom: 8 })

          Button(this.applying ? '…' : '微信支付')
            .width('100%')
            .height(48)
            .fontSize($r('app.float.body_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.accent'))
            .borderRadius($r('app.float.pill_radius'))
            .enabled(!this.applying)
            .onClick(() => {
              void this.onWeChatPay()
            })

          Column({ space: 8 }) {
            Text($r('app.string.qingyu_recharge_footer_note'))
              .fontSize(11)
              .fontColor($r('app.color.tertiary_text'))
              .width('100%')
              .lineHeight(17)
            Text($r('app.string.qingyu_recharge_agreement_link'))
              .fontSize(11)
              .fontColor($r('app.color.link_text'))
              .width('100%')
              .onClick(() => {
                this.openServiceAgreement()
              })
          }
          .width('100%')
          .constraintSize({ minWidth: 0 })
          .padding({
            top: 20,
            bottom: 32
          })
        }
        .width('100%')
        .constraintSize({ minWidth: 0 })
        .padding({ left: 16, right: 16 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
  }
}
