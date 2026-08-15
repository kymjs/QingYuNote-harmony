import { common } from '@kit.AbilityKit'
import { AppContextHolder } from './AppContextHolder'
import { Logger } from '../common/utils/Logger'
import { LocaleService } from './LocaleService'
import { NoteApiClient } from './NoteApiClient'
import { PreferencesService } from './PreferencesService'
import { QingyuAlipayPayService } from './QingyuAlipayPayService'
import { QingyuHuaweiIapPayService } from './QingyuHuaweiIapPayService'
import { QingyuHuaweiIapProducts } from '../common/constants/QingyuHuaweiIapProducts'
import type { QingyuRechargePlanId } from '../common/constants/QingyuRechargePlans'
import { RemoteAppConfigService } from './RemoteAppConfigService'
import { UserFacingMessage } from '../common/utils/UserFacingMessage'

export type QingyuVipPayStatus = 'success' | 'cancel' | 'fail' | 'pending'

export interface QingyuVipPayResult {
  status: QingyuVipPayStatus
  message: string
}

/** 轻羽云 VIP 支付（供 H5 Bridge 调用）。 */
export class QingyuVipPayService {
  private static instance: QingyuVipPayService = new QingyuVipPayService()
  private applying: boolean = false
  private useAlipayPay: boolean = false
  private payModeLoaded: boolean = false

  static getInstance(): QingyuVipPayService {
    return QingyuVipPayService.instance
  }

  async ensurePayModeLoaded(): Promise<void> {
    if (this.payModeLoaded) {
      return
    }
    const context = AppContextHolder.tryGetContext()
    const filesDir = context?.filesDir ?? ''
    this.useAlipayPay = await RemoteAppConfigService.alipayPayEnabledFromCache(filesDir)
    this.payModeLoaded = true
  }

  isApplying(): boolean {
    return this.applying
  }

  private parsePlanId(planId: string): QingyuRechargePlanId | null {
    const id = planId.trim()
    if (id === 'monthly' || id === 'half_year' || id === 'yearly' || id === 'lifetime') {
      return id as QingyuRechargePlanId
    }
    return null
  }

  /** App Store / 华为 IAP 路径下隐藏终身买断。 */
  async shouldHideLifetimePlan(): Promise<boolean> {
    await this.ensurePayModeLoaded()
    const useAlipay = this.useAlipayPay && QingyuAlipayPayService.isAliPayInstalled()
    return !useAlipay
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

  async startPay(planApiId: string): Promise<QingyuVipPayResult> {
    if (this.applying) {
      return { status: 'fail', message: LocaleService.loc('处理中…', 'Processing…', '処理中…') }
    }
    const plan = this.parsePlanId(planApiId)
    if (plan === null) {
      return { status: 'fail', message: LocaleService.loc('页面参数无效', 'Invalid params', 'パラメータが無効です') }
    }
    const ctx = AppContextHolder.tryGetContext()
    if (ctx === undefined) {
      return { status: 'fail', message: LocaleService.loc('请先登录后再充值', 'Please sign in first', '先にログインしてください') }
    }
    await PreferencesService.getInstance().init(ctx)
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return { status: 'fail', message: LocaleService.loc('请先登录后再充值', 'Please sign in first', '先にログインしてください') }
    }
    await this.ensurePayModeLoaded()
    const useAlipay = this.useAlipayPay && QingyuAlipayPayService.isAliPayInstalled()
    if (plan === 'lifetime') {
      if (!useAlipay) {
        return {
          status: 'fail',
          message: LocaleService.loc(
            '当前支付渠道不支持终身买断',
            'Lifetime plan is unavailable on this payment channel',
            'この決済では生涯プランを利用できません'
          )
        }
      }
      return await this.onAlipay(plan)
    }
    if (useAlipay) {
      return await this.onAlipay(plan)
    }
    return await this.onHuawei(ctx, plan)
  }

  private async createOrder(plan: QingyuRechargePlanId): Promise<number | null> {
    const order = await NoteApiClient.getInstance().createOrder(plan)
    const oid = order?.id
    if (order === null || oid === undefined || oid <= 0) {
      return null
    }
    return oid
  }

  private async onAlipay(plan: QingyuRechargePlanId): Promise<QingyuVipPayResult> {
    this.applying = true
    try {
      const api = NoteApiClient.getInstance()
      const oid = await this.createOrder(plan)
      if (oid === null) {
        return {
          status: 'fail',
          message: LocaleService.loc('创建订单失败，请稍后重试', 'Failed to create order', '注文の作成に失敗しました')
        }
      }
      const pr = await api.alipayAppPayOrderStr(oid)
      if (pr.status === 0) {
        Logger.warn('QingyuVipPayService', `alipay app-pay network failure orderId=${oid}`)
        return {
          status: 'fail',
          message: LocaleService.loc('网络异常，请稍后重试', 'Network error', 'ネットワークエラー')
        }
      }
      const body = pr.obj
      if (body === null) {
        return {
          status: 'fail',
          message: LocaleService.loc('获取支付参数失败，请稍后重试', 'Failed to get pay params', '支払いパラメータ取得失敗')
        }
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
        if (code === 'alipay_not_configured') {
          return {
            status: 'fail',
            message: LocaleService.loc('暂未开通支付', 'Payment unavailable', '支払い未設定')
          }
        }
        return {
          status: 'fail',
          message: UserFacingMessage.sanitize(human, '获取支付参数失败，请稍后重试')
        }
      }
      const orderStrRaw = rec['order_str']
      const appIdRaw = rec['app_id']
      const orderStr = typeof orderStrRaw === 'string' ? orderStrRaw.trim() : ''
      const appId = typeof appIdRaw === 'string' ? appIdRaw.trim() : ''
      if (orderStr.length === 0) {
        return {
          status: 'fail',
          message: LocaleService.loc('支付参数无效，请稍后重试', 'Invalid pay params', '支払いパラメータが無効です')
        }
      }
      const payResult =
        await QingyuAlipayPayService.payOrderStr(orderStr, appId.length > 0 ? appId : undefined)
      if (payResult === null) {
        return {
          status: 'fail',
          message: LocaleService.loc('支付未完成', 'Payment incomplete', '支払い未完了')
        }
      }
      const st = QingyuAlipayPayService.parseResultStatus(payResult)
      if (st === 6001) {
        return {
          status: 'cancel',
          message: LocaleService.loc('已取消支付', 'Payment canceled', '支払いをキャンセルしました')
        }
      }
      if (st !== undefined && st !== 9000 && st !== 8000) {
        const memo = (payResult.get('memo') ?? '').trim()
        return {
          status: 'fail',
          message: UserFacingMessage.sanitize(memo, '支付未完成，请稍后重试')
        }
      }
      const confirmed = await this.pollOrderPaid(oid)
      if (!confirmed) {
        return {
          status: 'pending',
          message: LocaleService.loc('支付确认中，请稍后返回刷新会员状态', 'Confirming payment…', '支払い確認中…')
        }
      }
      return {
        status: 'success',
        message: LocaleService.loc('支付成功', 'Payment successful', '支払い成功')
      }
    } finally {
      this.applying = false
    }
  }

  private async onHuawei(ctx: common.UIAbilityContext, plan: QingyuRechargePlanId): Promise<QingyuVipPayResult> {
    this.applying = true
    try {
      const api = NoteApiClient.getInstance()
      const oid = await this.createOrder(plan)
      if (oid === null) {
        return {
          status: 'fail',
          message: LocaleService.loc('创建订单失败，请稍后重试', 'Failed to create order', '注文の作成に失敗しました')
        }
      }
      const productId = QingyuHuaweiIapProducts.productId(plan)
      if (productId.length === 0) {
        return {
          status: 'fail',
          message: LocaleService.loc(
            '当前支付渠道不支持该套餐',
            'Plan unavailable on this payment channel',
            'この決済ではこのプランを利用できません'
          )
        }
      }
      const pay = await QingyuHuaweiIapPayService.createPurchase(ctx, productId)
      if (pay === null) {
        return {
          status: 'fail',
          message: LocaleService.loc('支付未完成', 'Payment incomplete', '支払い未完了')
        }
      }
      const vr = await api.huaweiVerifyOrder(oid, pay.purchaseToken, pay.productId, pay.accountFlag)
      if (vr.status === 0) {
        return {
          status: 'fail',
          message: LocaleService.loc('网络异常，请稍后重试', 'Network error', 'ネットワークエラー')
        }
      }
      if (!this.huaweiVerifySucceeded(vr.obj)) {
        return {
          status: 'fail',
          message: UserFacingMessage.forPaymentVerify(
            vr.obj,
            '支付校验未通过，如已扣款请稍后刷新会员状态或联系客服'
          )
        }
      }
      const confirmed = await this.pollOrderPaid(oid)
      void QingyuHuaweiIapPayService.finishPurchase(ctx, pay)
      if (!confirmed) {
        return {
          status: 'pending',
          message: LocaleService.loc('支付确认中，请稍后在会员中心刷新状态', 'Confirming payment…', '支払い確認中…')
        }
      }
      return {
        status: 'success',
        message: LocaleService.loc('支付成功', 'Payment successful', '支払い成功')
      }
    } finally {
      this.applying = false
    }
  }

  async buildSessionJson(locale: string): Promise<string> {
    let membershipKind = 'none'
    let expiresAt = ''
    let cta = 'subscribe'
    try {
      const guest = await PreferencesService.getInstance().isGuestMode()
      if (!guest) {
        const sub = await NoteApiClient.getInstance().fetchSubscription()
        const status = (sub?.state ?? '').trim()
        expiresAt = (sub?.expires_at ?? '').trim()
        if (status === 'lifetime' || sub?.is_lifetime === true) {
          membershipKind = 'lifetime'
          cta = 'renew'
        } else if (status === 'active') {
          membershipKind = 'active'
          cta = 'renew'
        } else if (status === 'expired') {
          membershipKind = 'expired'
        }
      }
    } catch (_) {
    }
    const hideLifetime = await this.shouldHideLifetimePlan()
    const userId: string = (await PreferencesService.getInstance().getNoteApiUserId()).trim()
    const payload: Record<string, Object> = {
      'type': 'session',
      'locale': locale,
      'membershipKind': membershipKind,
      'expiresAt': expiresAt,
      'cta': cta,
      'platform': 'harmony',
      'hideLifetime': hideLifetime,
      'showLifetime': !hideLifetime
    }
    if (userId.length > 0) {
      payload['userId'] = userId
    }
    return JSON.stringify(payload)
  }
}
