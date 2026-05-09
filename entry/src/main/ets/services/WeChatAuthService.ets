import type common from '@ohos.app.ability.common'
import { Want } from '@kit.AbilityKit'
import * as wxopensdk from '@tencent/wechat_open_sdk'
import { WECHAT_APP_ID } from '../common/constants/WeChatConstants'
import { AppContextHolder } from './AppContextHolder'
import { MergeAccountResponseBody, NoteApiClient } from './NoteApiClient'
import { PreferencesService } from './PreferencesService'
import { Logger } from '../common/utils/Logger'

/** Ability EventHub 事件名：微信授权返回结果（与页面订阅一致）。 */
export const WECHAT_LOGIN_RESULT_EVENT = 'wechat_login_result'

/** Ability EventHub：APP 微信支付回调结果（与充值页订阅一致）。 */
export const WECHAT_PAY_RESULT_EVENT = 'wechat_pay_result'

/** EventHub `emit` 传递的数据结构。 */
export interface WeChatLoginResultPayload {
  success: boolean
  code?: string
  errCode?: number
  errStr?: string
  /** 个人信息页「绑定微信」流程由服务端先 merge 再回传，供页面区分于普通登录。 */
  mergeResult?: MergeAccountResponseBody
}

/** `login`：code 换 JWT；`profile_merge`：将 code 对应身份合并到当前 Bearer 用户（已登录）。 */
export type WeChatOAuthIntent = 'login' | 'profile_merge'

let weChatOAuthIntent: WeChatOAuthIntent = 'login'

export function setWeChatOAuthIntent(intent: WeChatOAuthIntent): void {
  weChatOAuthIntent = intent
}

export function getWeChatOAuthIntent(): WeChatOAuthIntent {
  return weChatOAuthIntent
}

export interface WeChatPayResultPayload {
  errCode: number
  errStr?: string
}

export const wxApi: wxopensdk.WXApi = wxopensdk.WXAPIFactory.createWXAPI(WECHAT_APP_ID)

class WeChatAbilityHandler implements wxopensdk.WXApiEventHandler {
  onReq(_req: wxopensdk.BaseReq): void {
    // 登录/支付返回场景无需处理来自微信的 onReq
  }

  onResp(resp: wxopensdk.BaseResp): void {
    void this.dispatchResp(resp)
  }

  private async dispatchResp(resp: wxopensdk.BaseResp): Promise<void> {
    const hub = AppContextHolder.tryGetContext()?.eventHub
    if (resp.type === wxopensdk.Command.kCommandPay) {
      const pay = resp as wxopensdk.PayResp
      const payload: WeChatPayResultPayload = {
        errCode: pay.errCode,
        errStr: pay.errStr
      }
      hub?.emit(WECHAT_PAY_RESULT_EVENT, payload)
      return
    }

    const auth = resp as wxopensdk.SendAuthResp
    if (auth.errCode !== wxopensdk.ErrCode.ERR_OK) {
      weChatOAuthIntent = 'login'
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
      weChatOAuthIntent = 'login'
      hub?.emit(WECHAT_LOGIN_RESULT_EVENT, { success: false, errStr: '未返回授权码' } as WeChatLoginResultPayload)
      return
    }
    const intent = weChatOAuthIntent
    try {
      if (intent === 'profile_merge') {
        const merged = await NoteApiClient.getInstance().mergeAccountWithWeChatCode(code)
        if (merged === null || merged.ok !== true) {
          hub?.emit(WECHAT_LOGIN_RESULT_EVENT, {
            success: false,
            errStr: '绑定失败，请稍后重试'
          } as WeChatLoginResultPayload)
          return
        }
        await PreferencesService.getInstance().setWeChatLoggedIn(true)
        hub?.emit(WECHAT_LOGIN_RESULT_EVENT, {
          success: true,
          mergeResult: merged
        } as WeChatLoginResultPayload)
        return
      }
      const exchanged = await NoteApiClient.getInstance().exchangeWeChatCode(code)
      if (!exchanged) {
        hub?.emit(WECHAT_LOGIN_RESULT_EVENT, {
          success: false,
          errStr: '服务端登录失败，请稍后重试'
        } as WeChatLoginResultPayload)
        return
      }
    } catch (error) {
      Logger.warn('WeChatAuthService', `WeChat OAuth handler: ${JSON.stringify(error)}`)
      hub?.emit(WECHAT_LOGIN_RESULT_EVENT, {
        success: false,
        errStr: intent === 'profile_merge' ? '绑定失败，请稍后重试' : '服务端登录失败，请稍后重试'
      } as WeChatLoginResultPayload)
      return
    } finally {
      weChatOAuthIntent = 'login'
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

export function startWeChatAppPay(context: common.UIAbilityContext, req: wxopensdk.PayReq): boolean | Promise<boolean> {
  return wxApi.sendReq(context, req)
}
