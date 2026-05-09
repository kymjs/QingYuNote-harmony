import fs from '@ohos.file.fs'
import http from '@ohos.net.http'
import { NoteApiConstants } from '../common/constants/NoteApiConstants'
import { PreferencesService } from './PreferencesService'
import { Logger } from '../common/utils/Logger'

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
}

export interface WeChatPrepayBody {
  app_id?: string
  partner_id?: string
  prepay_id?: string
  package?: string
  nonce_str?: string
  timestamp?: string
  sign?: string
  sign_type?: string
}

/** `POST /api/v1/me/merge/*` 响应：action 为 noop（已绑定） / linked（新绑定） / merged（已并入另一账号）。 */
export interface MergeAccountResponseBody {
  ok?: boolean
  action?: string
  absorbed_user_id?: number
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

  private async requestJson(method: http.RequestMethod, path: string, body?: string, bearer?: string): Promise<Object | null> {
    const req = http.createHttp()
    try {
      const headers: Record<string, string> = {
        'Accept': 'application/json'
      }
      if (body !== undefined) {
        headers['Content-Type'] = 'application/json; charset=utf-8'
      }
      if (bearer !== undefined && bearer.length > 0) {
        headers['Authorization'] = `Bearer ${bearer}`
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

  /** 微信 OAuth code 换 JWT，并写入 Preferences（token + 平台 users.id）。 */
  async exchangeWeChatCode(code: string): Promise<boolean> {
    const trimmed = code.trim()
    if (trimmed.length === 0) {
      return false
    }
    const payload = JSON.stringify({ code: trimmed })
    const obj = await this.requestJson(http.RequestMethod.POST, '/api/v1/auth/wechat', payload, undefined)
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
    await PreferencesService.getInstance().setWeChatLoggedIn(true)
    return true
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
    const body: Record<string, string> = {
      'authorization_code': trimmed
    }
    const redir = (redirectUri ?? NoteApiConstants.huaweiOAuthRedirectUri).trim()
    if (redir.length > 0) {
      body['redirect_uri'] = redir
    }
    const payload = JSON.stringify(body)
    const obj = await this.requestJson(http.RequestMethod.POST, '/api/v1/auth/huawei', payload, undefined)
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
    const obj = await this.requestJson(http.RequestMethod.GET, '/api/v1/qingyu/webdav', undefined, tok)
    if (obj === null) {
      return null
    }
    return obj as QingyuWebDAVBody
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

  async wechatPrepay(orderId: number): Promise<WeChatPrepayBody | null> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return null
    }
    const path = `/api/v1/orders/${orderId}/wechat/prepay`
    const obj = await this.requestJson(http.RequestMethod.POST, path, JSON.stringify({}), tok)
    if (obj === null) {
      return null
    }
    return obj as WeChatPrepayBody
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
   * 将微信身份合并到当前登录账号；若该微信原属另一用户，则把对方账号数据并入（见服务端说明）。
   */
  async mergeAccountWithWeChatCode(code: string): Promise<MergeAccountResponseBody | null> {
    const trimmed = code.trim()
    if (trimmed.length === 0) {
      return null
    }
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return null
    }
    const obj = await this.requestJson(http.RequestMethod.POST, '/api/v1/me/merge/wechat', JSON.stringify({
      code: trimmed
    }), tok)
    if (obj === null) {
      return null
    }
    return obj as MergeAccountResponseBody
  }

  /**
   * 将华为身份合并到当前登录账号（凭据体与 link 相同，语义为可吸收另一用户）。
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
    const obj = await this.requestJson(http.RequestMethod.POST, '/api/v1/me/merge/huawei', JSON.stringify(body), tok)
    if (obj === null) {
      return null
    }
    return obj as MergeAccountResponseBody
  }

  async fetchProfile(): Promise<ProfileBody | null> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return null
    }
    const obj = await this.requestJson(http.RequestMethod.GET, '/api/v1/me/profile', undefined, tok)
    if (obj === null) {
      return null
    }
    return obj as ProfileBody
  }

  /**
   * PATCH /api/v1/me/profile；body 仅含需要修改的字段。
   * 返回 null 表示成功，否则为服务端 `error` 代码。
   */
  async patchProfile(body: Record<string, Object>): Promise<string | null> {
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return 'not_logged_in'
    }
    const keys = Object.keys(body)
    if (keys.length === 0) {
      return null
    }
    const req = http.createHttp()
    try {
      const resp = await req.request(this.joinUrl('/api/v1/me/profile'), {
        // NetStack 的 RequestMethod 无 PATCH 枚举，与 WebDAVClient 一样用字符串断言。
        method: 'PATCH' as http.RequestMethod,
        header: {
          'Accept': 'application/json',
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': `Bearer ${tok}`
        },
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000
      })
      const code = resp.responseCode
      const text = (resp.result as string) ?? ''
      if (code >= 200 && code < 300) {
        return null
      }
      return NoteApiClient.parseErrorCode(text)
    } catch (e) {
      Logger.warn('NoteApiClient', `patchProfile failed: ${JSON.stringify(e)}`)
      return 'network_error'
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

  /** 将 Apple 身份合并到当前登录账号。 */
  async mergeAccountWithAppleIdentityToken(identityToken: string): Promise<MergeAccountResponseBody | null> {
    const trimmed = identityToken.trim()
    if (trimmed.length === 0) {
      return null
    }
    const tok = await PreferencesService.getInstance().getNoteApiAccessToken()
    if (tok === null || tok.length === 0) {
      return null
    }
    const obj = await this.requestJson(
      http.RequestMethod.POST,
      '/api/v1/me/merge/apple',
      JSON.stringify({ identity_token: trimmed }),
      tok
    )
    if (obj === null) {
      return null
    }
    return obj as MergeAccountResponseBody
  }
}
