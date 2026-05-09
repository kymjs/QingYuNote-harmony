/**
 * 华为账号登录依赖 entry/module.json5 中 `metadata.client_id`：
 * 必须填写 **字面量** Client ID 字符串，不要使用 `$string:xxx` 资源引用，
 * 否则运行时无法解析，Account Kit 会报 Invalid appId / Invalid input parameter。
 * 数值须与 AGC「OAuth 2.0 客户端 ID」一致（多数应用与应用 App ID 相同；若不一致请填 OAuth 客户端 ID）。
 */
import type common from '@ohos.app.ability.common'
import { authentication } from '@kit.AccountKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { util } from '@kit.ArkTS'
import { Logger } from '../common/utils/Logger'
import { NoteApiClient } from './NoteApiClient'

/**
 * 拉起华为账号授权，仅返回 authorization_code（用于已登录用户绑定/合并，不调 POST /auth/huawei）。
 */
export async function obtainHuaweiAuthorizationCode(_context: common.UIAbilityContext): Promise<string> {
  const provider = new authentication.HuaweiIDProvider()
  const loginRequest = provider.createLoginWithHuaweiIDRequest()
  loginRequest.forceLogin = true
  loginRequest.state = util.generateRandomUUID()

  const controller = new authentication.AuthenticationController()
  let response: authentication.LoginWithHuaweiIDResponse
  try {
    response = await controller.executeRequest(loginRequest) as authentication.LoginWithHuaweiIDResponse
  } catch (err) {
    const be = err as BusinessError
    Logger.warn('HuaweiAuthService', `executeRequest failed: code=${be.code}, message=${be.message}`)
    throw new Error('华为账号登录失败，请重试')
  }

  if (response.state !== undefined && response.state.length > 0 && response.state !== loginRequest.state) {
    Logger.warn('HuaweiAuthService', 'state check failed for Huawei login')
    throw new Error('授权响应校验失败，请重试')
  }

  const credential = response.data
  const authorizationCode = credential?.authorizationCode?.trim() ?? ''
  if (authorizationCode.length === 0) {
    Logger.warn('HuaweiAuthService', 'authorizationCode is empty after Huawei login')
    throw new Error('未获得授权码，请重试')
  }
  return authorizationCode
}

/** 拉起华为账号登录；authorization_code 交由服务端换 JWT（与微信登录同一套账号体系）。 */
export async function startHuaweiLogin(_context: common.UIAbilityContext): Promise<void> {
  const authorizationCode = await obtainHuaweiAuthorizationCode(_context)
  const exchanged = await NoteApiClient.getInstance().exchangeHuaweiAuthorizationCode(authorizationCode)
  if (!exchanged) {
    Logger.warn('HuaweiAuthService', 'exchangeHuaweiAuthorizationCode failed (check Note API HUAWEI_* config)')
    throw new Error('登录失败：网络异常')
  }
}

export function describeHuaweiLoginError(error: Object): string {
  const be = error as BusinessError
  const code = typeof be.code === 'number' ? be.code : undefined
  const rawMsg = typeof be.message === 'string' ? be.message : ''
  if (code !== undefined) {
    Logger.warn('HuaweiAuthService', `Huawei login error code=${code}, message=${rawMsg}`)
  } else {
    Logger.warn('HuaweiAuthService', `Huawei login error: ${rawMsg.length > 0 ? rawMsg : JSON.stringify(error)}`)
  }
  const hintMap: Map<number, string> = new Map([
    [1001500001, '应用校验失败，请在 AGC 配置 SHA256 证书指纹并核对 Client ID'],
    [1001500002, '请勿重复发起登录'],
    [1001502001, '请先在本机登录华为账号'],
    [1001502005, '网络异常，请稍后重试'],
    [1001502012, '已取消授权'],
    [12300001, '系统服务异常，请稍后重试']
  ])
  if (code !== undefined) {
    const mapped = hintMap.get(code)
    if (mapped !== undefined && mapped.length > 0) {
      return mapped
    }
    if (rawMsg.length > 0) {
      return rawMsg
    }
  }
  const asErr = error as Error
  if (asErr.message !== undefined && `${asErr.message}`.length > 0) {
    return `${asErr.message}`
  }
  return '华为账号登录失败'
}
