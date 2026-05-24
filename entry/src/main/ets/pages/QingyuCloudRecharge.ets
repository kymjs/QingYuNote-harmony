import { Want } from '@kit.AbilityKit'
import type { WebDAVConfig } from '../common/model/Note'
import { AppContextHolder } from '../services/AppContextHolder'
import { PreferencesService } from '../services/PreferencesService'
import { Logger } from '../common/utils/Logger'
import { NoteApiClient } from '../services/NoteApiClient'
import { QingyuAlipayPayService } from '../services/QingyuAlipayPayService'
import { QingyuHuaweiIapPayService } from '../services/QingyuHuaweiIapPayService'
import { WebDAVClient } from '../services/WebDAVClient'
import type { QingyuRechargePlanId } from '../common/constants/QingyuRechargePlans'
import { QingyuRechargePlans } from '../common/constants/QingyuRechargePlans'
import { QingyuHuaweiIapProducts } from '../common/constants/QingyuHuaweiIapProducts'
import { RemoteAppConfigService } from '../services/RemoteAppConfigService'
import { UserFacingMessage } from '../common/utils/UserFacingMessage'

/**
 * 轻羽云服务 — 会员档位；支持华为应用内支付（IAP）与支付宝 App 支付。
 */
@Entry
@Component
struct QingyuCloudRecharge {
  @State selectedPlan: QingyuRechargePlanId = 'monthly'
  @State applying: boolean = false
  /** 与 Flutter 充值页一致：`active` / `lifetime` 为「续期」，否则「开通」。 */
  @State payPrimaryCtaLabel: string = '开  通'

  aboutToAppear(): void {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      void PreferencesService.getInstance().init(context)
    }
    void this.refreshPayPrimaryCtaLabel()
  }

  onPageShow(): void {
    void this.refreshPayPrimaryCtaLabel()
  }

  private async refreshPayPrimaryCtaLabel(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    if (await PreferencesService.getInstance().isGuestMode()) {
      this.payPrimaryCtaLabel = '开  通'
      return
    }
    try {
      const previewQingyu: WebDAVConfig = {
        baseUrl: '',
        username: '',
        encryptedPassword: '',
        notesDir: '/qingyu-notes/',
        enabled: true,
        provider: 'qingyu_cloud'
      }
      const status =
        await WebDAVClient.getInstance().fetchQingyuCloudSubscriptionStatus(previewQingyu)
      if (status.kind === 'active' || status.kind === 'lifetime') {
        this.payPrimaryCtaLabel = '续  期'
      } else {
        this.payPrimaryCtaLabel = '开  通'
      }
    } catch (_) {
      this.payPrimaryCtaLabel = '开  通'
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

  private huaweiVerifySucceeded(obj: Object | null): boolean {
    if (obj === null) {
      return false
    }
    const r = obj as Record<string, Object>
    if (r['payment_verified'] === false) {
      return false
    }
    const st = r['status']
    if (typeof st !== 'string') {
      return false
    }
    const s = st.trim()
    return s === 'paid' || s === 'already_paid'
  }

  private huaweiVerifyFailureMessage(obj: Object | null): string {
    return UserFacingMessage.forPaymentVerify(
      obj,
      '支付校验未通过，如已扣款请稍后刷新会员状态或联系客服'
    )
  }

  private async pollOrderPaid(orderId: number): Promise<boolean> {
    for (let i = 0; i < 45; i++) {
      await new Promise<void>((resolve) => setTimeout(resolve, 2000))
      const o = await NoteApiClient.getInstance().getOrder(orderId)
      if (o !== null && o.status === 'paid') {
        return true
      }
    }
    return false
  }

  private async createRechargeOrder(api: NoteApiClient): Promise<number | null> {
    const order = await api.createOrder(this.selectedPlan)
    const oid = order?.id
    if (order === null || oid === undefined || oid <= 0) {
      this.showToast('创建订单失败，请稍后重试')
      return null
    }
    return oid
  }

  private async onHuaweiPayTap(): Promise<void> {
    if (this.applying) {
      return
    }
    const ctx = AppContextHolder.tryGetContext()
    if (ctx === undefined) {
      this.showToast('请先登录账号')
      return
    }
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      this.showToast('请先登录账号')
      return
    }
    this.applying = true
    try {
      const api = NoteApiClient.getInstance()
      const oid = await this.createRechargeOrder(api)
      if (oid === null) {
        return
      }
      const productId = QingyuHuaweiIapProducts.productId(this.selectedPlan)
      const pay = await QingyuHuaweiIapPayService.createPurchase(ctx, productId)
      if (pay === null) {
        this.showToast('支付未完成')
        return
      }
      const vr = await api.huaweiVerifyOrder(oid, pay.purchaseToken, pay.productId, pay.accountFlag)
      if (vr.status === 0) {
        this.showToast('网络异常，请稍后重试')
        return
      }
      if (!this.huaweiVerifySucceeded(vr.obj)) {
        this.showToast(this.huaweiVerifyFailureMessage(vr.obj))
        return
      }
      const confirmed = await this.pollOrderPaid(oid)
      if (!confirmed) {
        this.showToast('支付确认中，请稍后在会员中心刷新状态')
      } else {
        this.showToast('支付成功')
      }
      void QingyuHuaweiIapPayService.finishPurchase(ctx, pay)
    } finally {
      this.applying = false
      void this.refreshPayPrimaryCtaLabel()
    }
  }

  private async onAlipayTap(): Promise<void> {
    if (this.applying) {
      return
    }
    const ctx = AppContextHolder.tryGetContext()
    if (ctx === undefined) {
      this.showToast('请先登录账号')
      return
    }
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      this.showToast('请先登录账号')
      return
    }
    this.applying = true
    try {
      const api = NoteApiClient.getInstance()
      const oid = await this.createRechargeOrder(api)
      if (oid === null) {
        return
      }
      const pr = await api.alipayAppPayOrderStr(oid)
      if (pr.status === 0) {
        Logger.warn('QingyuCloudRecharge', `alipay app-pay network failure orderId=${oid}`)
        this.showToast('网络异常，请稍后重试')
        return
      }
      const body = pr.obj
      if (body === null) {
        Logger.warn('QingyuCloudRecharge', `alipay app-pay HTTP ${pr.status} empty json orderId=${oid}`)
        this.showToast('获取支付参数失败，请稍后重试')
        return
      }
      const rec = body as Record<string, Object>
      const err = rec['error']
      if (typeof err === 'string' && err.trim().length > 0) {
        const code = err.trim()
        let human = ''
        const m = rec['message']
        if (typeof m === 'string' && m.trim().length > 0) {
          human = m.trim()
        }
        Logger.warn('QingyuCloudRecharge', `alipay app-pay orderId=${oid} error=${code} message=${human}`)
        if (code === 'alipay_not_configured') {
          this.showToast('暂未开通支付')
        } else {
          this.showToast(UserFacingMessage.sanitize(human, '获取支付参数失败，请稍后重试'))
        }
        return
      }
      const orderStrRaw = rec['order_str']
      const appIdRaw = rec['app_id']
      const orderStr = typeof orderStrRaw === 'string' ? orderStrRaw.trim() : ''
      const appId = typeof appIdRaw === 'string' ? appIdRaw.trim() : ''
      if (orderStr.length === 0) {
        Logger.warn('QingyuCloudRecharge', `alipay app-pay orderId=${oid} missing order_str`)
        this.showToast('支付参数无效，请稍后重试')
        return
      }
      const payResult =
        await QingyuAlipayPayService.payOrderStr(orderStr, appId.length > 0 ? appId : undefined)
      if (payResult === null) {
        this.showToast('支付未完成')
        return
      }
      const st = QingyuAlipayPayService.parseResultStatus(payResult)
      if (st === 6001) {
        this.showToast('已取消支付')
        return
      }
      if (st !== undefined && st !== 9000 && st !== 8000) {
        const memo = (payResult.get('memo') ?? '').trim()
        Logger.warn('QingyuCloudRecharge', `alipay sdk orderId=${oid} resultStatus=${st} memo=${memo}`)
        this.showToast(
          UserFacingMessage.sanitize(memo, '支付未完成，请稍后重试')
        )
        return
      }
      const confirmed = await this.pollOrderPaid(oid)
      if (!confirmed) {
        this.showToast('支付确认中，请稍后在会员中心刷新状态')
      } else {
        this.showToast('支付成功')
      }
    } finally {
      this.applying = false
      void this.refreshPayPrimaryCtaLabel()
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

          Column({ space: 10 }) {
            Button(this.applying ? '处理中…' : `华为 · ${this.payPrimaryCtaLabel}`)
              .width('100%')
              .height(48)
              .fontSize($r('app.float.body_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.accent'))
              .borderRadius($r('app.float.pill_radius'))
              .enabled(!this.applying)
              .visibility(Visibility.None)
              .onClick(() => {
                void this.onHuaweiPayTap()
              })
            Button(this.applying ? '处理中…' : this.payPrimaryCtaLabel)
              .width('100%')
              .height(48)
              .fontSize($r('app.float.body_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.accent'))
              .borderRadius($r('app.float.pill_radius'))
              .enabled(!this.applying)
              .onClick(() => {
                void this.onAlipayTap()
              })
          }
          .width('100%')
          .margin({ top: 20 })

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
