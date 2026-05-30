import router from '@ohos.router'
import { UIContext } from '@kit.ArkUI'

import { showConfirmAlertDialog } from '../../dialogs/ConfirmAlertDialog'
import { NoteApiClient, ProfileBody } from '../../services/NoteApiClient'
import { PreferencesService } from '../../services/PreferencesService'
import { RemoteAppConfigService } from '../../services/RemoteAppConfigService'
import { AppContextHolder } from '../../services/AppContextHolder'

const FEEDBACK_URL = 'pages/Feedback'

let betaTestInviteInFlight: boolean = false

function isQingyuMember(profile: ProfileBody): boolean {
  if (profile.membership_is_lifetime === true) {
    return true
  }
  const level = (profile.membership_level ?? '').trim()
  return level === 'active' || level === 'lifetime'
}

/**
 * 首页进入后：内测版本且未开通会员、未配置自建 WebDAV 时，一次性弹出内测邀请。
 */
export async function maybeShowBetaTestInviteDialog(uiContext: UIContext): Promise<void> {
  if (betaTestInviteInFlight) {
    return
  }
  betaTestInviteInFlight = true
  try {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    if (await PreferencesService.getInstance().hasBetaTestInviteDialogShown()) {
      return
    }
    const filesDir = context?.filesDir ?? ''
    if (!(await RemoteAppConfigService.readBetaTestConfigFromCache(filesDir))) {
      return
    }
    const loggedIn = await PreferencesService.getInstance().isUserLoggedIn()
    const guest = await PreferencesService.getInstance().isGuestMode()
    if (!loggedIn || guest) {
      return
    }
    if (await PreferencesService.getInstance().hasSavedCustomWebDAVConfig()) {
      return
    }

    let profile: ProfileBody | null = null
    try {
      profile = await NoteApiClient.getInstance().fetchProfile()
    } catch (_) {
      const cached = await PreferencesService.getInstance().getCachedUserProfile()
      if (cached !== null) {
        profile = cached as ProfileBody
      }
    }
    if (profile === null || isQingyuMember(profile)) {
      return
    }

    await PreferencesService.getInstance().setBetaTestInviteDialogShown(true)

    const confirmed = await showConfirmAlertDialog(uiContext, {
      title: '内测邀请',
      message: '尊贵的内测用户，感谢您的使用，添加作者微信可获赠一个月轻羽云会员。',
      cancelLabel: '取消',
      confirmLabel: '确定',
      confirmColor: '#0DAA4A'
    })
    if (confirmed) {
      uiContext.getRouter().pushUrl({
        url: FEEDBACK_URL,
        params: { fromBetaTestInvite: true }
      }).catch((err: Error) => {
        console.error(`pushUrl Feedback failed: ${JSON.stringify(err)}`)
      })
    }
  } catch (err) {
    console.error(`maybeShowBetaTestInviteDialog failed: ${JSON.stringify(err)}`)
  } finally {
    betaTestInviteInFlight = false
  }
}
