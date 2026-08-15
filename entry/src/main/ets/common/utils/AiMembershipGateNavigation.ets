import { UIContext } from '@kit.ArkUI'

import { showVipMembershipGateDialog } from '../../dialogs/VipMembershipGateDialog'
import { NoteApiClient, ProfileBody } from '../../services/NoteApiClient'
import { PreferencesService } from '../../services/PreferencesService'
import { AppContextHolder } from '../../services/AppContextHolder'
import { openQingyuVipPage } from './OpenQingyuVipPage'

function isQingyuMember(profile: ProfileBody): boolean {
  if (profile.membership_is_lifetime === true) {
    return true
  }
  const level = (profile.membership_level ?? '').trim()
  return level === 'active' || level === 'lifetime'
}

/** ISO 周键，形如 `2026-W33`（与 Flutter `aiMembershipGateIsoWeekKey` 对齐）。 */
export function aiMembershipGateIsoWeekKey(date: Date = new Date()): string {
  const day = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()))
  const weekday = day.getUTCDay() === 0 ? 7 : day.getUTCDay()
  const thursday = new Date(day)
  thursday.setUTCDate(day.getUTCDate() + (4 - weekday))
  const yearStart = new Date(Date.UTC(thursday.getUTCFullYear(), 0, 4))
  const yearStartWeekday = yearStart.getUTCDay() === 0 ? 7 : yearStart.getUTCDay()
  const week1Thursday = new Date(yearStart)
  week1Thursday.setUTCDate(yearStart.getUTCDate() + (4 - yearStartWeekday))
  const week =
    1 + Math.floor((thursday.getTime() - week1Thursday.getTime()) / (7 * 24 * 3600 * 1000))
  const weekStr = week < 10 ? `0${week}` : `${week}`
  return `${thursday.getUTCFullYear()}-W${weekStr}`
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
  void openQingyuVipPage(uiContext)
}

/**
 * 未开通轻羽云会员时拦截 AI 功能：每周首次弹窗，同周再次点击直达充值页。
 * @returns true 表示已开通会员，可继续执行 AI 逻辑。
 */
export async function ensureAiMembershipAccess(uiContext: UIContext): Promise<boolean> {
  const profile = await resolveUserProfile()
  if (profile !== null && isQingyuMember(profile)) {
    return true
  }

  const weekKey = aiMembershipGateIsoWeekKey()
  const shownWeek = await PreferencesService.getInstance().getAiMembershipGateDialogWeek()

  if (shownWeek !== weekKey) {
    await PreferencesService.getInstance().setAiMembershipGateDialogWeek(weekKey)
    const confirmed = await showVipMembershipGateDialog(uiContext)
    if (confirmed) {
      openQingyuRechargePage(uiContext)
    }
    return false
  }

  openQingyuRechargePage(uiContext)
  return false
}
