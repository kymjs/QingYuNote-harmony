import bundleManager from '@ohos.bundle.bundleManager'
import { Pay } from '@cashier_alipay/cashiersdk'
import { Logger } from '../common/utils/Logger'

/**
 * 轻羽云充值 — 支付宝 App 支付（orderStr 由服务端签发）。
 */
export class QingyuAlipayPayService {
  /** 是否已安装支付宝客户端（依赖 module.json5 中 `querySchemes: alipays`）。 */
  static isAliPayInstalled(): boolean {
    try {
      return bundleManager.canOpenLink('alipays://')
    } catch (e) {
      Logger.warn('QingyuAlipayPayService', `isAliPayInstalled: ${JSON.stringify(e)}`)
      return false
    }
  }

  /**
   * 唤起支付宝收银台。未安装支付宝时 SDK 可能走 H5（见官方 README）。
   */
  static async payOrderStr(orderStr: string, appId?: string): Promise<Map<string, string> | null> {
    const trimmed = orderStr.trim()
    if (trimmed.length === 0) {
      Logger.warn('QingyuAlipayPayService', 'orderStr empty')
      return null
    }
    try {
      const pay = new Pay()
      const aid = (appId ?? '').trim()
      if (aid.length > 0) {
        await pay.registerApp(aid)
      }
      return await pay.pay(trimmed, true)
    } catch (e) {
      Logger.warn('QingyuAlipayPayService', `pay: ${JSON.stringify(e)}`)
      return null
    }
  }

  static parseResultStatus(result: Map<string, string> | null): number | undefined {
    if (result === null) {
      return undefined
    }
    const raw = result.get('resultStatus')
    if (raw === undefined) {
      return undefined
    }
    const n = Number.parseInt(raw.trim(), 10)
    return Number.isFinite(n) ? n : undefined
  }
}
