import { UIContext } from '@kit.ArkUI'

import { showConfirmAlertDialog } from '../../dialogs/ConfirmAlertDialog'
import { NoteApiClient, ProfileBody } from '../../services/NoteApiClient'
import { PreferencesService } from '../../services/PreferencesService'
import { AppContextHolder } from '../../services/AppContextHolder'

const QINGYU_CLOUD_RECHARGE_URL = 'pages/QingyuCloudRecharge'
const AI_MEMBERSHIP_DIALOG_MESSAGE = 'AI功能需要开通轻羽云会员使用'

function isQingyuMember(profile: ProfileBody): boolean {
  if (profile.membership_is_lifetime === true) {
    return true
  }
  const level = (profile.membership_level ?? '').trim()
  return level === 'active' || level === 'lifetime'
}

async function resolveUserProfile(): Promise<ProfileBody | null> {
  const context = AppContextHolder.tryGetContext()
  if (context) {
    await PreferencesService.getInstance().init(context)
  }
  let profile: ProfileBody | null = null
  try {
    const loggedIn = await PreferencesService.getInstance().isUserLoggedIn()
    const guest = await PreferencesService.getInstance().isGuestMode()
    if (loggedIn && !guest) {
      profile = await NoteApiClient.getInstance().fetchProfile()
    }
  } catch (_) {
    const cached = await PreferencesService.getInstance().getCachedUserProfile()
    if (cached !== null) {
      profile = cached as ProfileBody
    }
  }
  if (profile === null) {
    const cached = await PreferencesService.getInstance().getCachedUserProfile()
    if (cached !== null) {
      profile = cached as ProfileBody
    }
  }
  return profile
}

function openQingyuRechargePage(uiContext: UIContext): void {
  uiContext.getRouter().pushUrl({ url: QINGYU_CLOUD_RECHARGE_URL }).catch((err: Error) => {
    console.error(`pushUrl QingyuCloudRecharge failed: ${JSON.stringify(err)}`)
  })
}

/**
 * 未开通轻羽云会员时拦截 AI 功能：首次弹窗提示，再次点击直达充值页。
 * @returns true 表示已开通会员，可继续执行 AI 逻辑。
 */
export async function ensureAiMembershipAccess(uiContext: UIContext): Promise<boolean> {
  const profile = await resolveUserProfile()
  if (profile !== null && isQingyuMember(profile)) {
    return true
  }

  const dialogShown = await PreferencesService.getInstance().hasAiMembershipGateDialogShown()

  if (!dialogShown) {
    await PreferencesService.getInstance().setAiMembershipGateDialogShown(true)
    const confirmed = await showConfirmAlertDialog(uiContext, {
      title: '提示',
      message: AI_MEMBERSHIP_DIALOG_MESSAGE,
      cancelLabel: '取消',
      confirmLabel: '确定',
      confirmColor: '#0DAA4A'
    })
    if (confirmed) {
      openQingyuRechargePage(uiContext)
    }
    return false
  }

  openQingyuRechargePage(uiContext)
  return false
}
