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
      return 50
    }
    return 73
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
      return '50 元 / 6 个月（另赠送 1 个月）'
    }
    return '73 元 / 年'
  }

  /** 横向档位卡片主标题（大字一行）。 */
  static cardHeadline(planId: QingyuRechargePlanId): string {
    if (planId === 'monthly') {
      return '¥10/月'
    }
    if (planId === 'half_year') {
      return '¥50/半年'
    }
    return '¥73/年'
  }

  /** 横向档位卡片副标题（小字一行）。 */
  static cardTagline(planId: QingyuRechargePlanId): string {
    if (planId === 'monthly') {
      return '体验试用 · 约 ¥0.33/天'
    }
    if (planId === 'half_year') {
      return '额外赠 1 个月 · 约 ¥7.1/月'
    }
    return ' 年度优选 · 约  ¥6 /月'
  }
}
