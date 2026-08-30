import { common, Want } from '@kit.AbilityKit'
import { UIContext } from '@kit.ArkUI'
import { AppContextHolder } from '../../services/AppContextHolder'
import { LocaleService } from '../../services/LocaleService'
import { PreferencesService } from '../../services/PreferencesService'

/** 官网用户反馈 H5（与 Flutter `AppConst.officialFeedbackPageUrl` 对齐）。 */
export const OFFICIAL_FEEDBACK_PAGE_URL: string = 'https://note.kymjs.com/feedback.html'

export function buildQingyuFeedbackPageUrl(): string {
  return OFFICIAL_FEEDBACK_PAGE_URL
}

export function isQingyuFeedbackPageUrl(url: string): boolean {
  const trimmed: string = url.trim()
  if (trimmed.length === 0) {
    return false
  }
  return trimmed.indexOf('note.kymjs.com/feedback') >= 0
}

function showToast(uiContext: UIContext, message: string): void {
  try {
    uiContext.getPromptAction().showToast({
      message: message,
      duration: 2500
    })
  } catch (_e) {
  }
}

/**
 * 打开用户反馈 H5：登录校验后内嵌 H5WebContainer。
 * Harmony 始终支持内嵌 WebView，故不走外部浏览器 + query 传参。
 */
export async function openQingyuFeedbackPage(uiContext: UIContext): Promise<void> {
  const context: common.UIAbilityContext | undefined = AppContextHolder.tryGetContext()
  if (context !== undefined) {
    await PreferencesService.getInstance().init(context)
  }
  const guest: boolean = await PreferencesService.getInstance().isGuestMode()
  const tok: string | null = await PreferencesService.getInstance().getNoteApiAccessToken()
  if (guest || tok === null || tok.length === 0) {
    showToast(
      uiContext,
      LocaleService.loc('请先登录后再反馈', 'Please sign in first', '先にログインしてください')
    )
    return
  }
  const title: string = LocaleService.loc('用户反馈', 'Feedback', 'フィードバック')
  const url: string = buildQingyuFeedbackPageUrl()
  try {
    await uiContext.getRouter().pushUrl({
      url: 'pages/H5WebContainer',
      params: {
        'title': title,
        'url': url
      }
    })
  } catch (err) {
    console.error(`openQingyuFeedbackPage: ${JSON.stringify(err)}`)
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: url
      }
      const ctx: common.UIAbilityContext | undefined = AppContextHolder.tryGetContext()
      if (ctx !== undefined) {
        await ctx.startAbility(want)
      }
    } catch (e) {
      console.error(`openQingyuFeedbackPage browser fallback: ${JSON.stringify(e)}`)
    }
  }
}
