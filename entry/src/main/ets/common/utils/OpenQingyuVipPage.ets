import { Want } from '@kit.AbilityKit'
import { UIContext } from '@kit.ArkUI'
import { AppContextHolder } from '../services/AppContextHolder'
import { LocaleService } from '../services/LocaleService'
import { PreferencesService } from '../services/PreferencesService'

/** 官网 VIP H5（与 Flutter `AppConst.officialVipPageUrl` 对齐）。 */
export const OFFICIAL_VIP_PAGE_URL = 'https://note.kymjs.com/vip.html'

export function vipPageLangQuery(): string {
  const lang = LocaleService.getInstance().getLanguage()
  if (lang === 'en') {
    return 'en'
  }
  if (lang === 'ja') {
    return 'ja'
  }
  if (lang === 'zh-Hant') {
    return 'zh-Hant'
  }
  return 'zh'
}

export function buildQingyuVipPageUrl(): string {
  return `${OFFICIAL_VIP_PAGE_URL}?lang=${encodeURIComponent(vipPageLangQuery())}`
}

export function isQingyuVipPageUrl(url: string): boolean {
  const trimmed = url.trim()
  if (trimmed.length === 0) {
    return false
  }
  return trimmed.indexOf('note.kymjs.com/vip') >= 0
}

function showToast(uiContext: UIContext, message: string): void {
  try {
    uiContext.getPromptAction().showToast({
      message,
      duration: 2500
    })
  } catch (_) {
  }
}

/**
 * 打开 VIP H5：登录校验后内嵌 H5WebContainer。
 * Harmony 始终支持内嵌 WebView，故不走外部浏览器 + ticket。
 */
export async function openQingyuVipPage(uiContext: UIContext): Promise<void> {
  const context = AppContextHolder.tryGetContext()
  if (context) {
    await PreferencesService.getInstance().init(context)
  }
  const guest = await PreferencesService.getInstance().isGuestMode()
  const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
  if (guest || tok === null || tok.length === 0) {
    showToast(
      uiContext,
      LocaleService.loc('请先登录后再充值', 'Please sign in first', '先にログインしてください')
    )
    return
  }
  const title = LocaleService.loc('轻羽云会员', 'Qingyu Membership', '軽羽会員')
  const url = buildQingyuVipPageUrl()
  try {
    await uiContext.getRouter().pushUrl({
      url: 'pages/H5WebContainer',
      params: {
        title: title,
        url: url
      }
    })
  } catch (err) {
    console.error(`openQingyuVipPage: ${JSON.stringify(err)}`)
    // 兜底：系统浏览器打开（无 Bridge，仅展示页）。
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: url
      }
      const ctx = AppContextHolder.tryGetContext()
      if (ctx) {
        await ctx.startAbility(want)
      }
    } catch (e) {
      console.error(`openQingyuVipPage browser fallback: ${JSON.stringify(e)}`)
    }
  }
}
