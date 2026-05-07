import type common from '@ohos.app.ability.common'
import { Want } from '@kit.AbilityKit'
import * as wxopensdk from '@tencent/wechat_open_sdk'
import { WECHAT_APP_ID } from '../common/constants/WeChatConstants'
import { AppContextHolder } from './AppContextHolder'
import { PreferencesService } from './PreferencesService'
import { Logger } from '../common/utils/Logger'

/** Ability EventHub 事件名：微信授权返回结果（与页面订阅一致）。 */
export const WECHAT_LOGIN_RESULT_EVENT = 'wechat_login_result'

/** EventHub `emit` 传递的数据结构。 */
export interface WeChatLoginResultPayload {
  success: boolean
  code?: string
  errCode?: number
  errStr?: string
}

export const wxApi: wxopensdk.WXApi = wxopensdk.WXAPIFactory.createWXAPI(WECHAT_APP_ID)

class WeChatAbilityHandler implements wxopensdk.WXApiEventHandler {
  onReq(_req: wxopensdk.BaseReq): void {
    // 登录场景无需处理来自微信的 onReq
  }

  onResp(resp: wxopensdk.BaseResp): void {
    void this.dispatchResp(resp)
  }

  private async dispatchResp(resp: wxopensdk.BaseResp): Promise<void> {
    const auth = resp as wxopensdk.SendAuthResp
    const hub = AppContextHolder.tryGetContext()?.eventHub
    if (auth.errCode !== wxopensdk.ErrCode.ERR_OK) {
      const payload: WeChatLoginResultPayload = {
        success: false,
        errCode: auth.errCode,
        errStr: auth.errStr
      }
      hub?.emit(WECHAT_LOGIN_RESULT_EVENT, payload)
      return
    }
    const code = auth.code?.trim() ?? ''
    if (code.length === 0) {
      hub?.emit(WECHAT_LOGIN_RESULT_EVENT, { success: false, errStr: '未返回授权码' } as WeChatLoginResultPayload)
      return
    }
    const openId = auth.openId?.trim() ?? ''
    const wxTail = openId.length > 0 ? openId : code
    if (openId.length === 0) {
      Logger.warn('WeChatAuthService', 'WeChat openId empty; persisting wx prefix with oauth code as fallback')
    }
    try {
      await PreferencesService.getInstance().setWeChatLoggedIn(true)
    } catch (_) {
      hub?.emit(WECHAT_LOGIN_RESULT_EVENT, { success: false, errStr: '保存登录状态失败' } as WeChatLoginResultPayload)
      return
    }
    try {
      await PreferencesService.getInstance().setWeChatThirdPartyUserId(`wx${wxTail}`)
    } catch (_) {
      Logger.warn('WeChatAuthService', 'setWeChatThirdPartyUserId failed after WeChat login')
    }
    hub?.emit(WECHAT_LOGIN_RESULT_EVENT, { success: true, code } as WeChatLoginResultPayload)
  }
}

export const weChatAbilityHandler = new WeChatAbilityHandler()

export function handleWeChatWant(want: Want): void {
  wxApi.handleWant(want, weChatAbilityHandler)
}

export function startWeChatLogin(context: common.UIAbilityContext): boolean | Promise<boolean> {
  const req = new wxopensdk.SendAuthReq()
  req.scope = 'snsapi_userinfo'
  req.state = 'qingyu_note_login'
  req.isOption1 = false
  req.nonAutomatic = false
  return wxApi.sendReq(context, req)
}
