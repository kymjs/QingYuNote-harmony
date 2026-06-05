import { UIContext } from '@kit.ArkUI'

import { showConfirmAlertDialog } from '../../dialogs/ConfirmAlertDialog'
import { NoteApiClient, ProfileBody } from '../../services/NoteApiClient'
import { PreferencesService } from '../../services/PreferencesService'
import { AppContextHolder } from '../../services/AppContextHolder'

const QINGYU_CLOUD_RECHARGE_URL = 'pages/QingyuCloudRecharge'

let membershipExpiryReminderInFlight: boolean = false

function localTodayYmd(): string {
  const d = new Date()
  const m = `${d.getMonth() + 1}`.padStart(2, '0')
  const day = `${d.getDate()}`.padStart(2, '0')
  return `${d.getFullYear()}-${m}-${day}`
}

function daysUntilMembershipExpiry(ymd: string): number | null {
  const t = ymd.trim()
  const matched = t.match(/^(\d{4})-(\d{2})-(\d{2})$/)
  if (matched === null) {
    return null
  }
  const exp = new Date(Number(matched[1]), Number(matched[2]) - 1, Number(matched[3]))
  const now = new Date()
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const expDay = new Date(exp.getFullYear(), exp.getMonth(), exp.getDate())
  return Math.round((expDay.getTime() - today.getTime()) / 86_400_000)
}

function remainingDaysForMembershipReminder(profile: ProfileBody): number | null {
  if (profile.membership_is_lifetime === true) {
    return null
  }
  const level = (profile.membership_level ?? '').trim()
  if (level !== 'active') {
    return null
  }
  const exp = (profile.membership_expires_at ?? '').trim()
  if (exp.length === 0) {
    return null
  }
  const days = daysUntilMembershipExpiry(exp)
  if (days === null || days < 0 || days >= 5) {
    return null
  }
  return days
}

function membershipExpiryReminderMessage(remainingDays: number): string {
  return `您的轻羽云服务只剩${remainingDays}天，为避免影响您正常使用，请及时充值。`
}

/**
 * 会员有效期内且剩余不足 5 天时：每设备每日首次进入笔记编辑/预览页弹出续费提醒。
 */
export async function maybeShowMembershipExpiryReminderDialog(
  uiContext: UIContext
): Promise<void> {
  if (membershipExpiryReminderInFlight) {
    return
  }
  membershipExpiryReminderInFlight = true
  try {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
    const today = localTodayYmd()
    if ((await PreferencesService.getInstance().getMembershipExpiryReminderLastShownYmd()) === today) {
      return
    }
    const loggedIn = await PreferencesService.getInstance().isUserLoggedIn()
    const guest = await PreferencesService.getInstance().isGuestMode()
    if (!loggedIn || guest) {
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
    const remainingDays = profile === null ? null : remainingDaysForMembershipReminder(profile)
    if (remainingDays === null) {
      return
    }

    await PreferencesService.getInstance().setMembershipExpiryReminderLastShownYmd(today)

    const confirmed = await showConfirmAlertDialog(uiContext, {
      title: '会员到期提醒',
      message: membershipExpiryReminderMessage(remainingDays),
      cancelLabel: '取消',
      confirmLabel: '确定',
      confirmColor: '#0DAA4A'
    })
    if (confirmed) {
      uiContext.getRouter().pushUrl({ url: QINGYU_CLOUD_RECHARGE_URL }).catch((err: Error) => {
        console.error(`pushUrl QingyuCloudRecharge failed: ${JSON.stringify(err)}`)
      })
    }
  } catch (err) {
    console.error(`maybeShowMembershipExpiryReminderDialog failed: ${JSON.stringify(err)}`)
  } finally {
    membershipExpiryReminderInFlight = false
  }
}
