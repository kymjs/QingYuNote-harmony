import type { QingyuRechargePlanId } from './QingyuRechargePlans'

/**
 * 华为 IAP 商品 ID（须与 AGC 应用内商品及服务端 HUAWEI_IAP_PRODUCT_* 一致）。
 * 默认与 iOS App Store 商品 ID 对齐。
 */
export class QingyuHuaweiIapProducts {
  static productId(plan: QingyuRechargePlanId): string {
    if (plan === 'monthly') {
      return 'com.kymjs.note.qingyu.monthly'
    }
    if (plan === 'half_year') {
      return 'com.kymjs.note.qingyu.half_year'
    }
    if (plan === 'lifetime') {
      // 终身买断不走华为 IAP
      return ''
    }
    return 'com.kymjs.note.qingyu.yearly'
  }
}
