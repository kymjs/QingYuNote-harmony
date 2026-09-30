import { common } from '@kit.AbilityKit'
import { UIContext } from '@kit.ArkUI'
import { AppContextHolder } from '../../services/AppContextHolder'
import { FeedbackReplyInbox } from '../../services/FeedbackReplyInbox'
import { LocaleService } from '../../services/LocaleService'
import { PreferencesService } from '../../services/PreferencesService'

/** 官网「我的反馈」H5（与 Flutter `AppConst.officialMyFeedbackPageUrl` 对齐）。 */
export const OFFICIAL_MY_FEEDBACK_PAGE_URL: string = 'https://note.kymjs.com/my-feedback.html'

export function isQingyuMyFeedbackPageUrl(url: string): boolean {
  const trimmed: string = url.trim()
  if (trimmed.length === 0) {
    return false
  }
  return trimmed.indexOf('note.kymjs.com/my-feedback') >= 0
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
 * 打开「我的反馈」H5：登录校验 → 刷新收件箱 → 标已读 → 内嵌 H5WebContainer。
 */
export async function openQingyuMyFeedbackPage(uiContext: UIContext): Promise<void> {
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
  await FeedbackReplyInbox.getInstance().refreshFromServer()
  if (!FeedbackReplyInbox.getInstance().hasReply()) {
    return
  }
  await FeedbackReplyInbox.getInstance().markCurrentRead()
  const title: string = LocaleService.loc('我的反馈', 'My feedback', '自分のフィードバック')
  try {
    await uiContext.getRouter().pushUrl({
      url: 'pages/H5WebContainer',
      params: {
        'title': title,
        'url': OFFICIAL_MY_FEEDBACK_PAGE_URL
      }
    })
  } catch (err) {
    console.error(`openQingyuMyFeedbackPage: ${JSON.stringify(err)}`)
  }
}
