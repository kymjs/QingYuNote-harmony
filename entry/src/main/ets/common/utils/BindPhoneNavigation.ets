import router from '@ohos.router'
import { UIContext } from '@kit.ArkUI'

import { NoteApiClient } from '../../services/NoteApiClient'
import { PreferencesService } from '../../services/PreferencesService'

const BIND_PHONE_URL = 'pages/BindPhone'

/** 进程内全局锁，避免首页多处并发触发重复 push。 */
let bindPhoneNavigationInFlight: boolean = false

/**
 * 已登录且未绑定手机号时进入绑定页；使用 RouterMode.Single 保证页面栈内唯一实例。
 */
export async function navigateToBindPhoneIfNeeded(uiContext: UIContext): Promise<void> {
  if (bindPhoneNavigationInFlight) {
    return
  }
  bindPhoneNavigationInFlight = true
  try {
    const loggedIn = await PreferencesService.getInstance().isUserLoggedIn()
    const guest = await PreferencesService.getInstance().isGuestMode()
    if (!loggedIn || guest) {
      return
    }
    const profile = await NoteApiClient.getInstance().fetchProfile()
    if (profile === null) {
      return
    }
    const phone = (profile.phone ?? '').trim()
    if (phone.length > 0) {
      return
    }
    const r = uiContext.getRouter()
    if (r.getStateByUrl(BIND_PHONE_URL).length > 0) {
      await r.pushUrl({ url: BIND_PHONE_URL }, router.RouterMode.Single)
      return
    }
    await r.pushUrl({ url: BIND_PHONE_URL }, router.RouterMode.Single)
  } catch (err) {
    console.error(`pushUrl BindPhone failed: ${JSON.stringify(err)}`)
  } finally {
    bindPhoneNavigationInFlight = false
  }
}
