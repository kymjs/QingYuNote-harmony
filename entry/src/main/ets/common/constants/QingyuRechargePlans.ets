/** 轻羽云会员充值档位（与充值页展示一致）。 */
export type QingyuRechargePlanId = 'monthly' | 'half_year' | 'yearly'

export class QingyuRechargePlans {
  static months(planId: QingyuRechargePlanId): number {
    if (planId === 'monthly') {
      return 1
    }
    if (planId === 'half_year') {
      return 7
    }
    return 12
  }

  static priceYuan(planId: QingyuRechargePlanId): number {
    if (planId === 'monthly') {
      return 10
    }
    if (planId === 'half_year') {
      return 60
    }
    return 100
  }

  static title(planId: QingyuRechargePlanId): string {
    if (planId === 'monthly') {
      return '月付'
    }
    if (planId === 'half_year') {
      return '半年'
    }
    return '年付'
  }

  static subtitle(planId: QingyuRechargePlanId): string {
    if (planId === 'monthly') {
      return '10 元 / 月'
    }
    if (planId === 'half_year') {
      return '60 元 / 7 个月（赠送 1 个月）'
    }
    return '100 元 / 年'
  }

  /** 横向档位卡片主标题（大字一行）。 */
  static cardHeadline(planId: QingyuRechargePlanId): string {
    if (planId === 'monthly') {
      return '¥10/月'
    }
    if (planId === 'half_year') {
      return '¥60/7个月'
    }
    return '¥100/年'
  }

  /** 横向档位卡片副标题（小字一行）。 */
  static cardTagline(planId: QingyuRechargePlanId): string {
    if (planId === 'monthly') {
      return '每月 ¥10 · 约 ¥0.33/天'
    }
    if (planId === 'half_year') {
      return '赠 1 个月 · 约 ¥8.6/月'
    }
    return '约 ¥8.3/月 · 年度优选'
  }
}
