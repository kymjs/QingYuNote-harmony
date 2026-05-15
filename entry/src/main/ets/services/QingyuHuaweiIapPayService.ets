import { iap } from '@kit.IAPKit'
import { BusinessError } from '@kit.BasicServicesKit'
import type common from '@ohos.app.ability.common'

/** 华为 IAP createPurchase 成功后用于服务端核销与 finishPurchase 的字段。 */
export interface QingyuHuaweiIapPurchasePayload {
  purchaseToken: string
  productId: string
  purchaseOrderId: string
  accountFlag: number
}

/** 与 IAP createPurchase 返回字段对齐，避免使用 ESObject（ArkTS arkts-no-any-unknown）。 */
interface HuaweiCreatePurchasePayloadRaw {
  purchaseToken?: string | number | boolean | Object
  purchaseOrderId?: string | number | boolean | Object
  productId?: string | number | boolean | Object
  accountFlag?: string | number | boolean | Object
}

function readTrimmedStringField(v: string | number | boolean | Object | undefined): string {
  if (typeof v === 'string') {
    return v.trim()
  }
  return ''
}

function readAccountFlagFromRaw(o: HuaweiCreatePurchasePayloadRaw): number {
  const v: string | number | boolean | Object | undefined = o.accountFlag
  if (typeof v === 'number' && Number.isFinite(v)) {
    return Math.trunc(v)
  }
  return 0
}

/**
 * 拉起华为应用内支付（消耗型），解析 createPurchase 结果。
 * 须在真机、已登录华为账号、AGC 已配置商品的环境下测试。
 */
export class QingyuHuaweiIapPayService {
  static parseCreatePurchaseResult(data: iap.CreatePurchaseResult,
    fallbackProductId: string): QingyuHuaweiIapPurchasePayload | null {
    const o = data as HuaweiCreatePurchasePayloadRaw
    const purchaseToken = readTrimmedStringField(o.purchaseToken)
    const purchaseOrderId = readTrimmedStringField(o.purchaseOrderId)
    let productId = readTrimmedStringField(o.productId)
    if (productId.length === 0) {
      productId = fallbackProductId.trim()
    }
    if (purchaseToken.length === 0) {
      return null
    }
    return {
      purchaseToken: purchaseToken,
      productId: productId,
      purchaseOrderId: purchaseOrderId,
      accountFlag: readAccountFlagFromRaw(o)
    }
  }

  static async createPurchase(ctx: common.UIAbilityContext,
    productId: string): Promise<QingyuHuaweiIapPurchasePayload | null> {
    const pid = productId.trim()
    if (pid.length === 0) {
      return null
    }
    const parameter: iap.PurchaseParameter = {
      productId: pid,
      productType: iap.ProductType.CONSUMABLE
    }
    try {
      const data: iap.CreatePurchaseResult = await iap.createPurchase(ctx, parameter)
      return QingyuHuaweiIapPayService.parseCreatePurchaseResult(data, pid)
    } catch (e) {
      const be = e as BusinessError
      console.error(`QingyuHuaweiIapPayService createPurchase code=${be?.code} message=${be?.message}`)
      return null
    }
  }

  /**
   * 服务端核销成功后调用，完成消耗型商品确认（与 IAP Kit finishPurchase 一致）。
   */
  static async finishPurchase(ctx: common.UIAbilityContext,
    payload: QingyuHuaweiIapPurchasePayload): Promise<boolean> {
    const parameter: iap.FinishPurchaseParameter = {
      productType: iap.ProductType.CONSUMABLE,
      purchaseToken: payload.purchaseToken,
      purchaseOrderId: payload.purchaseOrderId
    }
    try {
      await iap.finishPurchase(ctx, parameter)
      return true
    } catch (e) {
      const be = e as BusinessError
      console.error(`QingyuHuaweiIapPayService finishPurchase code=${be?.code} message=${be?.message}`)
      return false
    }
  }
}
