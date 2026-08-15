import fs from '@ohos.file.fs'
import http from '@ohos.net.http'
import { NoteApiConstants } from '../common/constants/NoteApiConstants'
import { PreferencesService } from './PreferencesService'
import { getAppVersionName } from './AppUpdateService'
import { handleServerUpgradeRequired } from './AppUpdateUi'
import { Logger } from '../common/utils/Logger'

/**
 * Note API HTTP 客户端。
 *
 * **公开短信频控（维护者）**：注册/重置密码发短信接口需要稳定的设备 ID；本类在
 * `sendPasswordResetSms`、`sendRegisterSms` 中设置 `X-Device-Id` 与 body `device_id`（与 Flutter Dio 拦截器一致）。
 * 服务端对 IP、手机号、设备三轴各滑动 24h 最多 3 次，详见仓库 `server/TECHNICAL.md` §2.11。
 * 对用户展示 `sms_quota_exceeded` 时勿暴露维度与数字。
 */

/** `POST /api/v1/auth/*` 登录成功响应（仅含 JWT、有效期与平台用户 id）。 */
export interface AuthLoginResponseBody {
  access_token?: string
  expires_in?: number
  user_id?: number
}

function parseAuthLoginUserId(obj: Object): string {
  const rec = obj as Record<string, Object>
  const v = rec['user_id']
  if (typeof v === 'number' && Number.isFinite(v)) {
    const n = Math.trunc(v)
    return n > 0 ? `${n}` : ''
  }
  if (typeof v === 'string') {
    const t = (v as string).trim()
    if (t.length > 0 && /^\d+$/.test(t)) {
      const n = Number.parseInt(t, 10)
      return !Number.isNaN(n) && n > 0 ? `${n}` : ''
    }
  }
  return ''
}

export interface SubscriptionBody {
  state?: string
  expires_at?: string
  is_lifetime?: boolean
}

export interface QingyuWebDAVBody {
  base_url?: string
  username?: string
  password?: string
  notes_dir?: string
}

export interface OrderBody {
  id?: number
  out_trade_no?: string
  plan_id?: string
  amount_total?: number
  status?: string
  /** 支付成功后为网关侧订单号（苹果 transactionId / 华为 orderId）。 */
  gateway_transaction_id?: string
}

/** `POST /api/v1/me/merge/*` 响应：action 为 noop / linked / relinked；冲突时 HTTP 409 且含 `rebind_ticket`。 */
export interface MergeAccountResponseBody {
  ok?: boolean
  action?: string
  absorbed_user_id?: number
  error?: string
  rebind_ticket?: string
}

/** `POST /api/v1/register/captcha/new` */
export interface RegisterCaptchaNewBody {
  captcha_id: string
  image_base64: string
}

/** `POST /api/v1/register` */
export interface PhoneRegisterRequestBody {
  phone: string
  sms_verify_code: string
  password: string
  referral_claim_token?: string
  inviter_phone?: string
}

/** `POST /api/v1/me/referral/popup/*` */
export interface ReferralPopupEventBody {
  variant: number
}

/** `POST /api/v1/me/sync-settings` */
export interface SyncSettingsRequestBody {
  sync_provider: string
  enabled: boolean
  base_url?: string
  notes_dir?: string
  username_enc?: string
  password_enc?: string
}

/** `POST /api/v1/me/redeem` 成功体 */
export interface RedeemSuccessBody {
  plan_id?: string
}

export type RedeemCodeResult = RedeemSuccessBody | string

/** `postAuthJsonStatus` 的 HTTP 状态与解析后的 JSON 对象。 */
export interface PostAuthJsonStatusResult {
  status: number
  obj: Object | null
}

/** MiniMax reasoning 配置 */
export interface AiTagReasoningConfig {
  effort: string
}

/** MiniMax thinking 配置 */
export interface MiniMaxThinkingConfig {
  type: string
}

/** MiniMax chat 额外参数 */
export interface MiniMaxChatExtras {
  reasoning?: AiTagReasoningConfig
  thinking?: MiniMaxThinkingConfig
}

/** `GET /api/v1/me/ai-tag-config` */
export interface AiTagConfigBody {
  token_plan_key: string
  model: string
  base_url: string
  reasoning?: AiTagReasoningConfig
}

/** MiniMax chat/completions 请求体 */
export interface ChatCompletionRequestBody {
  model: string
  temperature: number
  max_tokens: number
  reasoning_split: boolean
  messages: Object[]
  reasoning?: AiTagReasoningConfig
  thinking?: MiniMaxThinkingConfig
}

export function buildMiniMaxChatExtras(config: AiTagConfigBody): MiniMaxChatExtras {
  const effort = config.reasoning?.effort?.trim() ?? ''
  if (effort.length === 0) {
    const empty: MiniMaxChatExtras = {}
    return empty
  }
  const reasoning: AiTagReasoningConfig = { effort: effort }
  const extras: MiniMaxChatExtras = { reasoning: reasoning }
  if (effort === 'none') {
    const thinking: MiniMaxThinkingConfig = { type: 'disabled' }
    extras.thinking = thinking
  }
  return extras
}

export function buildChatCompletionRequestBody(
  model: string,
  temperature: number,
  maxTokens: number,
  reasoningSplit: boolean,
  messages: Object[],
  config: AiTagConfigBody
): ChatCompletionRequestBody {
  const body: ChatCompletionRequestBody = {
    model: model,
    temperature: temperature,
    max_tokens: maxTokens,
    reasoning_split: reasoningSplit,
    messages: messages
  }
  const extras = buildMiniMaxChatExtras(config)
  if (extras.reasoning !== undefined) {
    body.reasoning = extras.reasoning
  }
  if (extras.thinking !== undefined) {
    body.thinking = extras.thinking
  }
  return body
}

/** `GET /api/v1/me/profile` */
export interface ProfileBody {
  huawei_linked?: boolean
  wechat_linked?: boolean
  apple_linked?: boolean
  username?: string
  avatar_url?: string
  membership_level?: string
  membership_expires_at?: string
  membership_is_lifetime?: boolean
  registered_at?: string
  phone?: string
  email?: string
  password_set?: boolean
  qingyu_subscription_active?: boolean
  /** 服务端根据邀请弹窗曝光历史计算：会员为历史上从未曝光；非会员为当日未曝光 */
  invite_popup_pending?: boolean
}

export class NoteApiClient {
  private static instance: NoteApiClient = new NoteApiClient()

  static getInstance(): NoteApiClient {
    return NoteApiClient.instance
  }

  private joinUrl(path: string): string {
    const base = NoteApiConstants.baseUrl.replace(/\/+$/, '')
    const p = path.startsWith('/') ? path : `/${path}`
    return `${base}${p}`
  }

  /** 与 WebDAVClient.pickHeader 对齐：读取 ArkTS HttpResponse header（大小写不敏感）。 */
  private pickHeader(headers: Object, key: string): string {
    const headerRecord = headers as Record<string, Object | string | number | boolean | undefined>
    const normalizedKey = key.toLowerCase()
    for (const headerKey of Object.keys(headerRecord)) {
      if (headerKey.toLowerCase() !== normalizedKey) {
        continue
      }
      const value = headerRecord[headerKey]
      if (typeof value === 'string') {
        return value
      }
      if (typeof value === 'number' || typeof value === 'boolean') {
        return `${value}`
      }
      if (Array.isArray(value) && value.length > 0) {
        return `${value[0]}`
      }
    }
    return ''
  }

  private static cachedAppVersion: string = ''

  private static handleUpgradeRequiredBody(bodyText: string): void {
    let minVersion: string | undefined = undefined
    let downloadUrl: string | undefined = undefined
    if (bodyText.trim().length > 0) {
      try {
        const obj = JSON.parse(bodyText) as Record<string, Object>
        const mv = obj['min_version']
        if (typeof mv === 'string' && mv.trim().length > 0) {
          minVersion = mv.trim()
        }
        const du = obj['download_url']
        if (typeof du === 'string' && du.trim().length > 0) {
          downloadUrl = du.trim()
        }
      } catch (_) {
      }
    }
    void handleServerUpgradeRequired(undefined, minVersion, downloadUrl)
  }

  /** 统一处理 HTTP 426；返回 true 表示已触发强更 UI，调用方应中止后续逻辑。 */
  static interceptUpgradeRequired(httpStatus: number, bodyText: string): boolean {
    if (httpStatus !== 426) {
      return false
    }
    NoteApiClient.handleUpgradeRequiredBody(bodyText)
    return true
  }

  /** 构建通用请求头，包含 X-Platform、X-Device-Id 与 X-App-Version。 */
  private async buildCommonHeaders(): Promise<Record<string, string>> {
    const headers: Record<string, string> = {
      'Accept': 'application/json',
      'X-Platform': 'harmony'
    }
    if (NoteApiClient.cachedAppVersion.length === 0) {
      try {
        NoteApiClient.cachedAppVersion = (await getAppVersionName()).trim()
      } catch (_) {}
    }
    if (NoteApiClient.cachedAppVersion.length > 0) {
      headers['X-App-Version'] = NoteApiClient.cachedAppVersion
    }
    let devId = ''
    try {
      devId = await PreferencesService.getInstance().getOrCreateSmsDeviceId()
    } catch (_) {}
    if (devId.trim().length > 0) {
      headers['X-Device-Id'] = devId.trim()
    }
    return headers
  }

  private async postAuthJsonStatus(path: string, bodyJson: string, bearer: string): Promise<PostAuthJsonStatusResult> {
    const req = http.createHttp()
    try {
      const headers = await this.buildCommonHeaders()
      headers['Content-Type'] = 'application/json; charset=utf-8'
      headers['Authorization'] = `Bearer ${bearer}`
      const resp = await req.request(this.joinUrl(path), {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: bodyJson,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000
      })
      const status = resp.responseCode
      const text = (resp.result as string) ?? ''
      if (NoteApiClient.interceptUpgradeRequired(status, text)) {
        const blocked: PostAuthJsonStatusResult = { status: status, obj: null }
        return blocked
      }
      let obj: Object | null = null
      if (text.trim().length > 0) {
        try {
          obj = JSON.parse(text) as Object
        } catch (_) {
          obj = null
        }
      }
      const ok: PostAuthJsonStatusResult = { status: status, obj: obj }
      return ok
    } catch (e) {
      Logger.warn('NoteApiClient', `postAuthJsonStatus ${path}: ${JSON.stringify(e)}`)
      const err: PostAuthJsonStatusResult = { status: 0, obj: null }
      return err
    } finally {
      req.destroy()
    }
  }

  private async requestJson(method: http.RequestMethod, path: string, body?: string, bearer?: string): Promise<Object | null> {
    return this.requestJsonWithHeaders(method, path, body, bearer, undefined)
  }

  private async requestJsonWithHeaders(method: http.RequestMethod, path: string, body: string | undefined, bearer: string | undefined, extraHeaders: Record<string, string> | undefined): Promise<Object | null> {
    const req = http.createHttp()
    try {
      const headers = await this.buildCommonHeaders()
      if (body !== undefined) {
        headers['Content-Type'] = 'application/json; charset=utf-8'
      }
      if (bearer !== undefined && bearer.length > 0) {
        headers['Authorization'] = `Bearer ${bearer}`
      }
      if (extraHeaders !== undefined) {
        for (const key of Object.keys(extraHeaders)) {
          headers[key] = extraHeaders[key]
        }
      }
      const resp = await req.request(this.joinUrl(path), {
        method,
        header: headers,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000
      })
      const code = resp.responseCode
      const text = (resp.result as string) ?? ''
      if (NoteApiClient.interceptUpgradeRequired(code, text)) {
        return null
      }
      if (code < 200 || code >= 300) {
        Logger.warn('NoteApiClient', `HTTP ${code} ${path} body=${text.slice(0, 400)}`)
        return null
      }
      if (text.trim().length === 0) {
        return null
      }
      return JSON.parse(text) as Object
    } catch (e) {
      Logger.warn('NoteApiClient', `request failed ${path}: ${JSON.stringify(e)}`)
      return null
    } finally {
      req.destroy()
    }
  }

  /**
   * 华为 authorization_code 换 JWT（服务端换华为 token），写入 Preferences。
   * redirect_uri 未配置时请与服务端 HUAWEI_REDIRECT_URI 同为空或同为 AGC 回调地址。
   */
  async exchangeHuaweiAuthorizationCode(code: string, redirectUri?: string): Promise<boolean> {
    const trimmed = code.trim()
    if (trimmed.length === 0) {
      return false
    }
    let devId = ''
    try {
      devId = await PreferencesService.getInstance().getOrCreateSmsDeviceId()
    } catch (_) {}
    const body: Record<string, string> = {
      'authorization_code': trimmed
    }
    const redir = (redirectUri ?? NoteApiConstants.huaweiOAuthRedirectUri).trim()
    if (redir.length > 0) {
      body['redirect_uri'] = redir
    }
    const payload = JSON.stringify(body)
    const headers = await this.buildCommonHeaders()
    headers['Content-Type'] = 'application/json; charset=utf-8'
    const obj = await this.requestJsonWithHeaders(http.RequestMethod.POST, '/api/v1/auth/huawei', payload, undefined, headers)
    if (obj === null) {
      return false
    }
    const raw = obj as AuthLoginResponseBody
    const token = raw.access_token?.trim() ?? ''
    const expiresIn = raw.expires_in ?? 604800
    const uid = parseAuthLoginUserId(obj)
    if (token.length === 0 || uid.length === 0) {
      return false
    }
    await PreferencesService.getInstance().setNoteApiSession(token, expiresIn)
    await PreferencesService.getInstance().setNoteApiUserId(uid)
    await PreferencesService.getInstance().setHuaweiLoggedIn(true)
    return true
  }

  /**
   * POST /api/v1/auth/phone：手机号 + 密码换 JWT；成功返回 null，否则为服务端 error 码。
   */
  async loginWithPhonePassword(phone: string, password: string): Promise<string | null> {
    const pPhone = phone.trim()
    const pPwd = password.trim()
    if (pPhone.length === 0 || pPwd.length === 0) {
      return 'invalid_body'
    }
    let devId = ''
    try {
      devId = await PreferencesService.getInstance().getOrCreateSmsDeviceId()
    } catch (_) {}
    const req = http.createHttp()
    try {
      const headers = await this.buildCommonHeaders()
      headers['Content-Type'] = 'application/json; charset=utf-8'
      const resp = await req.request(this.joinUrl('/api/v1/auth/phone'), {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify({ phone: pPhone, password: pPwd }),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000
      })
      const httpCode = resp.responseCode
      const text = (resp.result as string) ?? ''
      if (NoteApiClient.interceptUpgradeRequired(httpCode, text)) {
        return 'upgrade_required'
      }
      if (httpCode >= 200 && httpCode < 300) {
        let obj: Object
        try {
          obj = JSON.parse(text) as Object
        } catch (_) {
          return 'unknown_error'
        }
        const raw = obj as AuthLoginResponseBody
        const token = raw.access_token?.trim() ?? ''
        const expiresIn = raw.expires_in ?? 604800
        const uid = parseAuthLoginUserId(obj)
        if (token.length === 0 || uid.length === 0) {
          return 'unknown_error'
        }
        await PreferencesService.getInstance().setNoteApiSession(token, expiresIn)
        await PreferencesService.getInstance().setNoteApiUserId(uid)
        return null
      }
      return NoteApiClient.parseErrorCode(text)
    } catch (e) {
      Logger.warn('NoteApiClient', `loginWithPhonePassword failed: ${JSON.stringify(e)}`)
      return 'network_error'
    } finally {
      req.destroy()
    }
  }

  async fetchSubscription(): Promise<SubscriptionBody | null> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return null
    }
    const obj = await this.requestJson(http.RequestMethod.GET, '/api/v1/me/subscription', undefined, tok)
    if (obj === null) {
      return null
    }
    return obj as SubscriptionBody
  }

  async fetchQingyuWebDAV(): Promise<QingyuWebDAVBody | null> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return null
    }
    let waitMs = 0
    for (let attempt = 0; attempt < 3; attempt += 1) {
      if (waitMs > 0) {
        await new Promise<void>((resolve) => setTimeout(resolve, waitMs))
      }
      const req = http.createHttp()
      try {
        const headers = await this.buildCommonHeaders()
        headers['Authorization'] = `Bearer ${tok}`
        const resp = await req.request(this.joinUrl('/api/v1/qingyu/webdav'), {
          method: http.RequestMethod.GET,
          header: headers,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 15000,
          readTimeout: 20000
        })
        const code = resp.responseCode
        const text = (resp.result as string) ?? ''
        if (NoteApiClient.interceptUpgradeRequired(code, text)) {
          return null
        }
        if (code >= 200 && code < 300 && text.trim().length > 0) {
          try {
            return JSON.parse(text) as QingyuWebDAVBody
          } catch (e) {
            Logger.warn('NoteApiClient', `fetchQingyuWebDAV JSON parse failed: ${JSON.stringify(e)}`)
            waitMs = attempt === 0 ? 450 : 900
            continue
          }
        }
        if (code === 429) {
          const rawRa = this.pickHeader(resp.header, 'retry-after').trim()
          const sec = Number.parseInt(rawRa, 10)
          const bounded =
            Number.isFinite(sec) && sec > 0 ? Math.min(Math.max(sec, 1), 120) * 1000 : (attempt === 0 ? 2000 : 5000)
          waitMs = bounded
          Logger.info('NoteApiClient',
            `GET /api/v1/qingyu/webdav rate limited (429), will retry after ${waitMs}ms (attempt ${attempt + 1}/3)`)
          continue
        }
        Logger.warn('NoteApiClient', `HTTP ${code} /api/v1/qingyu/webdav body=${text.slice(0, 400)}`)
        waitMs = attempt < 2 ? 450 : 0
      } catch (e) {
        Logger.warn('NoteApiClient', `fetchQingyuWebDAV request failed: ${JSON.stringify(e)}`)
        waitMs = attempt < 2 ? 450 : 0
      } finally {
        req.destroy()
      }
    }
    return null
  }

  async createOrder(planId: string): Promise<OrderBody | null> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return null
    }
    const obj =
      await this.requestJson(http.RequestMethod.POST, '/api/v1/orders', JSON.stringify({ plan_id: planId }), tok)
    if (obj === null) {
      return null
    }
    return obj as OrderBody
  }

  async getOrder(orderId: number): Promise<OrderBody | null> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return null
    }
    const path = `/api/v1/orders/${orderId}`
    const obj = await this.requestJson(http.RequestMethod.GET, path, undefined, tok)
    if (obj === null) {
      return null
    }
    return obj as OrderBody
  }

  /**
   * 获取支付宝 App 支付 orderStr（`alipay.trade.app.pay`），与 Android/Flutter 一致。
   * 成功时 HTTP 200 且 JSON 含 `order_str`、`app_id`；配置缺失等为 503 等，body 仍可能为 JSON。
   */
  async alipayAppPayOrderStr(orderId: number): Promise<PostAuthJsonStatusResult> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      const empty: PostAuthJsonStatusResult = { status: 0, obj: null }
      return empty
    }
    return await this.postAuthJsonStatus(`/api/v1/orders/${orderId}/alipay/app-pay`, '{}', tok)
  }

  /** 签发外部浏览器 VIP 页一次性支付票（与 Flutter `createH5PayTicket` 对齐）。 */
  async createH5PayTicket(): Promise<string | null> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return null
    }
    const obj = await this.requestJson(http.RequestMethod.POST, '/api/v1/me/h5-pay-ticket', '{}', tok)
    if (obj === null) {
      return null
    }
    const rec = obj as Record<string, Object>
    const ticket = rec['ticket']
    if (typeof ticket === 'string' && ticket.trim().length > 0) {
      return ticket.trim()
    }
    return null
  }

  /**
   * 上报华为 IAP purchaseToken，服务端调 AGC 校验后标记订单已支付并顺延订阅。
   * 4xx 时仍可能返回 JSON（含 payment_verified），请用 PostAuthJsonStatusResult 读取 status。
   */
  async huaweiVerifyOrder(orderId: number, purchaseToken: string, productId: string,
    accountFlag: number): Promise<PostAuthJsonStatusResult> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      const empty: PostAuthJsonStatusResult = { status: 0, obj: null }
      return empty
    }
    const payload: Record<string, string | number> = {
      'purchase_token': purchaseToken.trim(),
      'product_id': productId.trim(),
      'account_flag': accountFlag
    }
    return await this.postAuthJsonStatus(
      `/api/v1/orders/${orderId}/huawei/verify`,
      JSON.stringify(payload),
      tok
    )
  }

  /**
   * 将华为身份绑定到当前登录账号；若已绑定到其他用户则返回 409 与 `rebind_ticket`。
   */
  async mergeAccountWithHuaweiAuthorizationCode(code: string, redirectUri?: string): Promise<MergeAccountResponseBody | null> {
    const trimmed = code.trim()
    if (trimmed.length === 0) {
      return null
    }
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return null
    }
    const body: Record<string, string> = { 'authorization_code': trimmed }
    const redir = (redirectUri ?? NoteApiConstants.huaweiOAuthRedirectUri).trim()
    if (redir.length > 0) {
      body['redirect_uri'] = redir
    }
    const mergeHuawei = await this.postAuthJsonStatus(
      '/api/v1/me/merge/huawei',
      JSON.stringify(body),
      tok
    )
    const status = mergeHuawei.status
    const obj = mergeHuawei.obj
    if (obj === null) {
      return null
    }
    if (status === 200 || status === 409) {
      return obj as MergeAccountResponseBody
    }
    return null
  }

  async fetchAiTagConfig(): Promise<AiTagConfigBody | null> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return null
    }
    const obj = await this.requestJson(http.RequestMethod.GET, '/api/v1/me/ai-tag-config', undefined, tok)
    if (obj === null) {
      return null
    }
    const record = obj as Record<string, Object>
    const key = `${record['token_plan_key'] ?? ''}`.trim()
    const model = `${record['model'] ?? 'MiniMax-M2.7'}`.trim()
    const baseUrl = `${record['base_url'] ?? 'https://api.minimaxi.com/v1'}`.trim()
    if (key.length === 0 || model.length === 0) {
      return null
    }
    let reasoning: AiTagReasoningConfig | undefined = undefined
    const reasoningRaw = record['reasoning'] as Record<string, Object> | undefined
    if (reasoningRaw !== undefined) {
      const effort = `${reasoningRaw['effort'] ?? ''}`.trim()
      if (effort.length > 0) {
        const reasoningConfig: AiTagReasoningConfig = { effort: effort }
        reasoning = reasoningConfig
      }
    }
    const body: AiTagConfigBody = {
      token_plan_key: key,
      model: model,
      base_url: baseUrl,
      reasoning: reasoning
    }
    return body
  }

  async fetchProfile(): Promise<ProfileBody | null> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return null
    }
    const obj = await this.requestJson(http.RequestMethod.GET, '/api/v1/me/profile', undefined, tok)
    if (obj === null) {
      const cached = await PreferencesService.getInstance().getCachedUserProfile()
      return cached !== null ? cached as ProfileBody : null
    }
    const profile = obj as ProfileBody
    await PreferencesService.getInstance().saveCachedUserProfile(obj as Record<string, Object>)
    return profile
  }

  async reportReferralPopupImpression(variant: number): Promise<void> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return
    }
    const body: ReferralPopupEventBody = { variant: variant }
    await this.requestJson(http.RequestMethod.POST, '/api/v1/me/referral/popup/impression',
      JSON.stringify(body), tok)
  }

  async reportReferralPopupClick(variant: number): Promise<void> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return
    }
    const body: ReferralPopupEventBody = { variant: variant }
    await this.requestJson(http.RequestMethod.POST, '/api/v1/me/referral/popup/click',
      JSON.stringify(body), tok)
  }

  /**
   * POST /api/v1/me/redeem。
   * 成功返回对象（含 plan_id）；失败返回服务端 error 字符串；网络异常返回 null。
   */
  async redeemCode(code: string): Promise<RedeemCodeResult | null> {
    const trimmed = code.trim()
    if (trimmed.length === 0) {
      return 'invalid_body'
    }
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return 'not_logged_in'
    }
    const req = http.createHttp()
    try {
      const resp = await req.request(this.joinUrl('/api/v1/me/redeem'), {
        method: http.RequestMethod.POST,
        header: {
          'Accept': 'application/json',
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': `Bearer ${tok}`
        },
        extraData: JSON.stringify({ code: trimmed }),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000
      })
      const httpCode = resp.responseCode
      const text = (resp.result as string) ?? ''
      if (NoteApiClient.interceptUpgradeRequired(httpCode, text)) {
        return 'upgrade_required'
      }
      if (httpCode >= 200 && httpCode < 300) {
        try {
          return JSON.parse(text) as RedeemSuccessBody
        } catch (_) {
          return 'unknown_error'
        }
      }
      return NoteApiClient.parseErrorCode(text)
    } catch (e) {
      Logger.warn('NoteApiClient', `redeemCode failed: ${JSON.stringify(e)}`)
      return null
    } finally {
      req.destroy()
    }
  }

  /**
   * POST /api/v1/me/profile/phone/sms/send：向填写的目标手机号发送验证码（资料页绑定/改号）。
   * 须先通过图形验证码（与注册发短信一致）。
   */
  async sendProfilePhoneSms(phone: string, captchaId: string, captchaCode: string): Promise<string | null> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return 'not_logged_in'
    }
    const trimmed = phone.trim()
    if (trimmed.length === 0) {
      return 'empty_phone'
    }
    const req = http.createHttp()
    try {
      const resp = await req.request(this.joinUrl('/api/v1/me/profile/phone/sms/send'), {
        method: http.RequestMethod.POST,
        header: {
          'Accept': 'application/json',
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': `Bearer ${tok}`
        },
        extraData: JSON.stringify({
          phone: trimmed,
          captcha_id: captchaId.trim(),
          captcha_code: captchaCode.trim()
        }),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000
      })
      const code = resp.responseCode
      const text = (resp.result as string) ?? ''
      if (NoteApiClient.interceptUpgradeRequired(code, text)) {
        return 'upgrade_required'
      }
      if (code >= 200 && code < 300) {
        return null
      }
      Logger.warn('NoteApiClient', `sendProfilePhoneSms HTTP ${code} body=${text.slice(0, 500)}`)
      return NoteApiClient.parseErrorCode(text)
    } catch (e) {
      Logger.warn('NoteApiClient', `sendProfilePhoneSms failed: ${JSON.stringify(e)}`)
      return 'network_error'
    } finally {
      req.destroy()
    }
  }

  /**
   * POST /api/v1/me/password/sms/send：向账号绑定手机号发送修改密码验证码。
   * 成功返回 null，否则为服务端 `error` 代码。
   */
  async sendPasswordSms(phone: string): Promise<string | null> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return 'not_logged_in'
    }
    const trimmed = phone.trim()
    if (trimmed.length === 0) {
      return 'empty_phone'
    }
    const req = http.createHttp()
    try {
      const resp = await req.request(this.joinUrl('/api/v1/me/password/sms/send'), {
        method: http.RequestMethod.POST,
        header: {
          'Accept': 'application/json',
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': `Bearer ${tok}`
        },
        extraData: JSON.stringify({ phone: trimmed }),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000
      })
      const code = resp.responseCode
      const text = (resp.result as string) ?? ''
      if (NoteApiClient.interceptUpgradeRequired(code, text)) {
        return 'upgrade_required'
      }
      if (code >= 200 && code < 300) {
        return null
      }
      Logger.warn('NoteApiClient', `sendPasswordSms HTTP ${code} body=${text.slice(0, 500)}`)
      return NoteApiClient.parseErrorCode(text)
    } catch (e) {
      Logger.warn('NoteApiClient', `sendPasswordSms failed: ${JSON.stringify(e)}`)
      return 'network_error'
    } finally {
      req.destroy()
    }
  }

  /**
   * POST /api/v1/password/reset/check-phone：无需登录。
   * 返回 true/false；网络或解析失败返回 null。
   */
  async checkPasswordResetRegistered(phone: string): Promise<boolean | null> {
    const trimmed = phone.trim()
    if (trimmed.length === 0) {
      return null
    }
    const req = http.createHttp()
    try {
      const resp = await req.request(this.joinUrl('/api/v1/password/reset/check-phone'), {
        method: http.RequestMethod.POST,
        header: {
          'Accept': 'application/json',
          'Content-Type': 'application/json; charset=utf-8'
        },
        extraData: JSON.stringify({ phone: trimmed }),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000
      })
      const code = resp.responseCode
      const text = (resp.result as string) ?? ''
      if (NoteApiClient.interceptUpgradeRequired(code, text)) {
        return null
      }
      if (code >= 200 && code < 300) {
        try {
          const obj = JSON.parse(text) as Record<string, Object>
          const r = obj['registered']
          if (typeof r === 'boolean') {
            return r
          }
        } catch (_) {
          return null
        }
        return null
      }
      Logger.warn('NoteApiClient', `checkPasswordResetRegistered HTTP ${code} body=${text.slice(0, 500)}`)
      return null
    } catch (e) {
      Logger.warn('NoteApiClient', `checkPasswordResetRegistered failed: ${JSON.stringify(e)}`)
      return null
    } finally {
      req.destroy()
    }
  }

  /**
   * POST /api/v1/password/reset/sms/send：无需登录。
   */
  async sendPasswordResetSms(phone: string): Promise<string | null> {
    const trimmed = phone.trim()
    if (trimmed.length === 0) {
      return 'empty_phone'
    }
    let dev = ''
    try {
      dev = await PreferencesService.getInstance().getOrCreateSmsDeviceId()
    } catch (_) {
      dev = ''
    }
    const req = http.createHttp()
    try {
      const headers = await this.buildCommonHeaders()
      headers['Content-Type'] = 'application/json; charset=utf-8'
      const resp = await req.request(this.joinUrl('/api/v1/password/reset/sms/send'), {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify({ phone: trimmed, device_id: dev.trim() }),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000
      })
      const code = resp.responseCode
      const text = (resp.result as string) ?? ''
      if (NoteApiClient.interceptUpgradeRequired(code, text)) {
        return 'upgrade_required'
      }
      if (code >= 200 && code < 300) {
        return null
      }
      Logger.warn('NoteApiClient', `sendPasswordResetSms HTTP ${code} body=${text.slice(0, 500)}`)
      return NoteApiClient.parseErrorCode(text)
    } catch (e) {
      Logger.warn('NoteApiClient', `sendPasswordResetSms failed: ${JSON.stringify(e)}`)
      return 'network_error'
    } finally {
      req.destroy()
    }
  }

  /**
   * POST /api/v1/password/reset：无需登录，短信核验后重置密码。
   */
  async resetPasswordWithSms(phone: string, smsVerifyCode: string, newPassword: string): Promise<string | null> {
    const req = http.createHttp()
    try {
      const resp = await req.request(this.joinUrl('/api/v1/password/reset'), {
        method: http.RequestMethod.POST,
        header: {
          'Accept': 'application/json',
          'Content-Type': 'application/json; charset=utf-8'
        },
        extraData: JSON.stringify({
          phone: phone.trim(),
          sms_verify_code: smsVerifyCode.trim(),
          new_password: newPassword.trim()
        }),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000
      })
      const code = resp.responseCode
      const text = (resp.result as string) ?? ''
      if (NoteApiClient.interceptUpgradeRequired(code, text)) {
        return 'upgrade_required'
      }
      if (code >= 200 && code < 300) {
        return null
      }
      Logger.warn('NoteApiClient', `resetPasswordWithSms HTTP ${code} body=${text.slice(0, 500)}`)
      return NoteApiClient.parseErrorCode(text)
    } catch (e) {
      Logger.warn('NoteApiClient', `resetPasswordWithSms failed: ${JSON.stringify(e)}`)
      return 'network_error'
    } finally {
      req.destroy()
    }
  }

  /**
   * POST /api/v1/register/captcha/new：获取图形验证码 PNG（base64）。
   */
  async fetchRegisterCaptchaNew(): Promise<RegisterCaptchaNewBody | null> {
    const req = http.createHttp()
    try {
      const resp = await req.request(this.joinUrl('/api/v1/register/captcha/new'), {
        method: http.RequestMethod.POST,
        header: {
          'Accept': 'application/json',
          'Content-Type': 'application/json; charset=utf-8'
        },
        extraData: '{}',
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000
      })
      const code = resp.responseCode
      const text = ((resp.result as string) ?? '').trim()
      if (NoteApiClient.interceptUpgradeRequired(code, text)) {
        return null
      }
      if (code >= 200 && code < 300) {
        try {
          const obj = JSON.parse(text) as Record<string, Object>
          const id = obj['captcha_id']
          const b64 = obj['image_base64']
          if (typeof id === 'string' && typeof b64 === 'string') {
            const tid = id.trim()
            const tb64 = b64.trim()
            if (tid.length > 0 && tb64.length > 0) {
              return { captcha_id: tid, image_base64: tb64 }
            }
          }
        } catch (e) {
          Logger.warn('NoteApiClient', `fetchRegisterCaptchaNew JSON parse: ${JSON.stringify(e)} head=${text.slice(0, 120)}`)
          return null
        }
        return null
      }
      Logger.warn('NoteApiClient', `fetchRegisterCaptchaNew HTTP ${code} body=${text.slice(0, 500)}`)
      return null
    } catch (e) {
      Logger.warn('NoteApiClient', `fetchRegisterCaptchaNew failed: ${JSON.stringify(e)}`)
      return null
    } finally {
      req.destroy()
    }
  }

  /**
   * POST /api/v1/register/sms/send：无需登录；须先通过图形验证码，且仅当手机号尚未注册时发送验证码。
   */
  async sendRegisterSms(phone: string, captchaId: string, captchaCode: string): Promise<string | null> {
    const trimmed = phone.trim()
    const cid = captchaId.trim()
    const ccode = captchaCode.trim()
    if (trimmed.length === 0) {
      return 'empty_phone'
    }
    if (cid.length === 0 || ccode.length === 0) {
      return 'invalid_body'
    }
    let dev = ''
    try {
      dev = await PreferencesService.getInstance().getOrCreateSmsDeviceId()
    } catch (_) {
      dev = ''
    }
    const req = http.createHttp()
    try {
      const headers = await this.buildCommonHeaders()
      headers['Content-Type'] = 'application/json; charset=utf-8'
      const resp = await req.request(this.joinUrl('/api/v1/register/sms/send'), {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify({
          phone: trimmed,
          captcha_id: cid,
          captcha_code: ccode,
          device_id: dev.trim()
        }),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000
      })
      const code = resp.responseCode
      const text = (resp.result as string) ?? ''
      if (NoteApiClient.interceptUpgradeRequired(code, text)) {
        return 'upgrade_required'
      }
      if (code >= 200 && code < 300) {
        return null
      }
      Logger.warn('NoteApiClient', `sendRegisterSms HTTP ${code} body=${text.slice(0, 500)}`)
      return NoteApiClient.parseErrorCode(text)
    } catch (e) {
      Logger.warn('NoteApiClient', `sendRegisterSms failed: ${JSON.stringify(e)}`)
      return 'network_error'
    } finally {
      req.destroy()
    }
  }

  /**
   * POST /api/v1/register：无需登录，短信核验后创建账号并写入会话（与手机号登录一致）。
   */
  async registerWithPhoneSms(
    phone: string,
    smsVerifyCode: string,
    password: string,
    referralClaimToken?: string,
    inviterPhone?: string
  ): Promise<string | null> {
    const pPhone = phone.trim()
    const pCode = smsVerifyCode.trim()
    const pPwd = password.trim()
    if (pPhone.length === 0 || pCode.length === 0 || pPwd.length === 0) {
      return 'invalid_body'
    }
    const body: PhoneRegisterRequestBody = {
      phone: pPhone,
      sms_verify_code: pCode,
      password: pPwd
    }
    const claim = referralClaimToken?.trim() ?? ''
    if (claim.length > 0) {
      body.referral_claim_token = claim
    }
    const inviter = inviterPhone?.trim() ?? ''
    if (inviter.length > 0) {
      body.inviter_phone = inviter
    }
    let devId = ''
    try {
      devId = await PreferencesService.getInstance().getOrCreateSmsDeviceId()
    } catch (_) {}
    const req = http.createHttp()
    try {
      const headers = await this.buildCommonHeaders()
      headers['Content-Type'] = 'application/json; charset=utf-8'
      const resp = await req.request(this.joinUrl('/api/v1/register'), {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000
      })
      const httpCode = resp.responseCode
      const text = (resp.result as string) ?? ''
      if (NoteApiClient.interceptUpgradeRequired(httpCode, text)) {
        return 'upgrade_required'
      }
      if (httpCode >= 200 && httpCode < 300) {
        let obj: Object
        try {
          obj = JSON.parse(text) as Object
        } catch (_) {
          return 'unknown_error'
        }
        const raw = obj as AuthLoginResponseBody
        const token = raw.access_token?.trim() ?? ''
        const expiresIn = raw.expires_in ?? 604800
        const uid = parseAuthLoginUserId(obj)
        if (token.length === 0 || uid.length === 0) {
          return 'unknown_error'
        }
        await PreferencesService.getInstance().setNoteApiSession(token, expiresIn)
        await PreferencesService.getInstance().setNoteApiUserId(uid)
        return null
      }
      return NoteApiClient.parseErrorCode(text)
    } catch (e) {
      Logger.warn('NoteApiClient', `registerWithPhoneSms failed: ${JSON.stringify(e)}`)
      return 'network_error'
    } finally {
      req.destroy()
    }
  }

  /**
   * POST /api/v1/me/profile（与 PATCH 同语义；Harmony @ohos.net.http 无 PATCH 枚举）。
   * body 仅含需要修改的字段。返回 null 表示成功，否则为服务端 `error` 代码。
   * 5xx 与请求异常统一返回 network_error，不透传服务端 error 字段。
   * @param refreshProfile 成功后是否刷新本地 profile 缓存（多步绑定/改号时中间步可传 false，减少并发请求）。
   */
  async patchProfile(body: Record<string, Object>, refreshProfile: boolean = true): Promise<string | null> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return 'not_logged_in'
    }
    const keys = Object.keys(body)
    if (keys.length === 0) {
      return null
    }
    const payload = JSON.stringify(body)
    let waitMs = 0
    for (let attempt = 0; attempt < 3; attempt += 1) {
      if (waitMs > 0) {
        await new Promise<void>((resolve) => setTimeout(resolve, waitMs))
      }
      const req = http.createHttp()
      try {
        const headers = await this.buildCommonHeaders()
        headers['Content-Type'] = 'application/json; charset=utf-8'
        headers['Authorization'] = `Bearer ${tok}`
        const resp = await req.request(this.joinUrl('/api/v1/me/profile'), {
          method: http.RequestMethod.POST,
          header: headers,
          extraData: payload,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 15000,
          readTimeout: 20000
        })
        const code = resp.responseCode
        const text = (resp.result as string) ?? ''
        if (NoteApiClient.interceptUpgradeRequired(code, text)) {
          return 'upgrade_required'
        }
        if (code >= 200 && code < 300) {
          if (refreshProfile) {
            void this.fetchProfile()
          }
          return null
        }
        const errCode = NoteApiClient.parseErrorCode(text)
        // 4xx 为业务错误，不重试。
        if (code >= 400 && code < 500) {
          Logger.warn('NoteApiClient', `patchProfile HTTP ${code} error=${errCode} body=${text.slice(0, 400)}`)
          return errCode
        }
        Logger.warn('NoteApiClient',
          `patchProfile HTTP ${code} attempt=${attempt + 1}/3 error=${errCode} body=${text.slice(0, 400)}`)
        waitMs = attempt < 2 ? 450 : 0
      } catch (e) {
        Logger.warn('NoteApiClient', `patchProfile request failed attempt=${attempt + 1}/3: ${JSON.stringify(e)}`)
        waitMs = attempt < 2 ? 450 : 0
      } finally {
        req.destroy()
      }
    }
    return 'network_error'
  }

  /** POST /api/v1/me/sync-settings：上报云同步方案（WebDAV 私密字段客户端加密）。 */
  async putSyncSettings(
    syncProvider: string,
    enabled: boolean,
    baseUrl: string = '',
    notesDir: string = '',
    usernameEnc: string = '',
    passwordEnc: string = ''
  ): Promise<void> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return
    }
    const body: SyncSettingsRequestBody = {
      sync_provider: syncProvider,
      enabled: enabled
    }
    if (syncProvider === 'webdav') {
      body.base_url = baseUrl
      body.notes_dir = notesDir
      body.username_enc = usernameEnc
      body.password_enc = passwordEnc
    }
    const payload = JSON.stringify(body)
    const req = http.createHttp()
    try {
      const headers = await this.buildCommonHeaders()
      headers['Content-Type'] = 'application/json; charset=utf-8'
      headers['Authorization'] = `Bearer ${tok}`
      const resp = await req.request(this.joinUrl('/api/v1/me/sync-settings'), {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: payload,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000
      })
      const code = resp.responseCode
      const text = (resp.result as string) ?? ''
      if (NoteApiClient.interceptUpgradeRequired(code, text)) {
        return
      }
    } catch (e) {
      Logger.warn('NoteApiClient', `putSyncSettings failed: ${JSON.stringify(e)}`)
    } finally {
      req.destroy()
    }
  }

  /**
   * POST /api/v1/me/avatar：multipart 字段名 `file`。
   * 成功返回 null，否则为服务端 `error` 代码（与 patchProfile 一致）。
   */
  async uploadAvatar(localPath: string): Promise<string | null> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return 'not_logged_in'
    }
    let sz = 0
    try {
      sz = fs.statSync(localPath).size
    } catch (e) {
      Logger.warn('NoteApiClient', `uploadAvatar stat failed: ${JSON.stringify(e)}`)
      return 'network_error'
    }
    if (sz <= 0) {
      return 'empty_file'
    }
    const buf = new ArrayBuffer(sz)
    try {
      const f = fs.openSync(localPath, fs.OpenMode.READ_ONLY)
      try {
        fs.readSync(f.fd, buf)
      } finally {
        fs.closeSync(f)
      }
    } catch (e) {
      Logger.warn('NoteApiClient', `uploadAvatar read failed: ${JSON.stringify(e)}`)
      return 'network_error'
    }
    const mime = NoteApiClient.guessMimeForAvatarPath(localPath)
    const boundary = `----NoteAvatar${Date.now()}`
    const body = NoteApiClient.buildAvatarMultipartBody(buf, mime, boundary)
    const req = http.createHttp()
    try {
      const resp = await req.request(this.joinUrl('/api/v1/me/avatar'), {
        method: http.RequestMethod.POST,
        header: {
          'Accept': 'application/json',
          'Authorization': `Bearer ${tok}`,
          'Content-Type': `multipart/form-data; boundary=${boundary}`
        },
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 60000,
        readTimeout: 120000
      })
      const code = resp.responseCode
      const text = (resp.result as string) ?? ''
      if (NoteApiClient.interceptUpgradeRequired(code, text)) {
        return 'upgrade_required'
      }
      if (code >= 200 && code < 300) {
        return null
      }
      // Nginx 等反代默认 client_max_body_size 常为 1m，先于 Go 返回 413 HTML，无法解析 JSON error
      if (code === 413) {
        return 'gateway_body_too_large'
      }
      Logger.warn('NoteApiClient', `upload avatar HTTP ${code} ${text.slice(0, 400)}`)
      return NoteApiClient.parseErrorCode(text)
    } catch (e) {
      Logger.warn('NoteApiClient', `uploadAvatar failed: ${JSON.stringify(e)}`)
      return 'network_error'
    } finally {
      req.destroy()
    }
  }

  private static guessMimeForAvatarPath(p: string): string {
    const lower = p.toLowerCase()
    if (lower.endsWith('.png')) {
      return 'image/png'
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif'
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp'
    }
    return 'image/jpeg'
  }

  /** multipart 头尾仅为 ASCII；不用 TextEncoder.encodeInto，避免部分系统版本返回空 Uint8Array 导致整段非 multipart。 */
  private static multipartAsciiBytes(s: string): Uint8Array {
    const out = new Uint8Array(s.length)
    for (let i = 0; i < s.length; i++) {
      out[i] = s.charCodeAt(i) & 0xff
    }
    return out
  }

  private static buildAvatarMultipartBody(fileBuf: ArrayBuffer, mime: string, boundary: string): ArrayBuffer {
    const crlf = '\r\n'
    // 服务端只校验字段名 `file` 与魔数；filename 固定为 ASCII，避免中文路径与编码差异。
    const headStr =
      `--${boundary}${crlf}` +
      `Content-Disposition: form-data; name="file"; filename="avatar.jpg"${crlf}` +
      `Content-Type: ${mime}${crlf}${crlf}`
    const tailStr = `${crlf}--${boundary}--${crlf}`
    const head = NoteApiClient.multipartAsciiBytes(headStr)
    const tail = NoteApiClient.multipartAsciiBytes(tailStr)
    const mid = new Uint8Array(fileBuf)
    const out = new Uint8Array(head.length + mid.length + tail.length)
    out.set(head, 0)
    out.set(mid, head.length)
    out.set(tail, head.length + mid.length)
    return out.buffer.slice(out.byteOffset, out.byteOffset + out.byteLength)
  }

  /** DELETE /api/v1/me，注销账号。成功返回 null，否则为 error 代码。 */
  async deleteAccount(): Promise<string | null> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return 'not_logged_in'
    }
    const req = http.createHttp()
    try {
      const resp = await req.request(this.joinUrl('/api/v1/me'), {
        method: http.RequestMethod.DELETE,
        header: {
          'Accept': 'application/json',
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': `Bearer ${tok}`
        },
        extraData: JSON.stringify({ confirm: 'delete_account' }),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 60000,
        readTimeout: 120000
      })
      const code = resp.responseCode
      const text = (resp.result as string) ?? ''
      if (NoteApiClient.interceptUpgradeRequired(code, text)) {
        return 'upgrade_required'
      }
      if (code >= 200 && code < 300) {
        return null
      }
      return NoteApiClient.parseErrorCode(text)
    } catch (e) {
      Logger.warn('NoteApiClient', `deleteAccount failed: ${JSON.stringify(e)}`)
      return 'network_error'
    } finally {
      req.destroy()
    }
  }

  private static parseErrorCode(text: string): string {
    const t = text.trim()
    if (t.length === 0) {
      return 'unknown_error'
    }
    try {
      const obj = JSON.parse(t) as Record<string, Object>
      const e = obj['error']
      if (typeof e === 'string' && e.length > 0) {
        return e
      }
    } catch (_) {
      // ignore
    }
    return 'unknown_error'
  }

  /** 确认 `rebind_ticket`，将第三方身份从其他账号解绑并绑定到当前用户。 */
  async confirmIdentityRebind(rebindTicket: string): Promise<MergeAccountResponseBody | null> {
    const trimmed = rebindTicket.trim()
    if (trimmed.length === 0) {
      return null
    }
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return null
    }
    const rebind = await this.postAuthJsonStatus(
      '/api/v1/me/rebind/identity/confirm',
      JSON.stringify({ rebind_ticket: trimmed }),
      tok
    )
    const status = rebind.status
    const obj = rebind.obj
    if (obj === null || status !== 200) {
      return null
    }
    return obj as MergeAccountResponseBody
  }

  /** 将 Apple 身份绑定到当前登录账号；冲突时返回 409 与 `rebind_ticket`。 */
  async mergeAccountWithAppleIdentityToken(identityToken: string): Promise<MergeAccountResponseBody | null> {
    const trimmed = identityToken.trim()
    if (trimmed.length === 0) {
      return null
    }
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return null
    }
    const mergeApple = await this.postAuthJsonStatus(
      '/api/v1/me/merge/apple',
      JSON.stringify({ identity_token: trimmed }),
      tok
    )
    const status = mergeApple.status
    const obj = mergeApple.obj
    if (obj === null) {
      return null
    }
    if (status === 200 || status === 409) {
      return obj as MergeAccountResponseBody
    }
    return null
  }
}
