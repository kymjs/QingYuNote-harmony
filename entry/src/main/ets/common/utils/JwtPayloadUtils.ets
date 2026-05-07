import { util } from '@kit.ArkTS'

/**
 * 仅用于解析 idToken 中用户标识，不做签名校验（与业务侧仅取 sub 使用场景一致）。
 */
export class JwtPayloadUtils {
  private static readonly base64: util.Base64Helper = new util.Base64Helper()

  static extractSubFromIdToken(jwt: string): string {
    const payload = JwtPayloadUtils.decodePayloadRecord(jwt)
    if (payload === null) {
      return ''
    }
    const sub = payload['sub']
    if (typeof sub === 'string' && sub.trim().length > 0) {
      return sub.trim()
    }
    return ''
  }

  private static decodePayloadRecord(jwt: string): Record<string, Object> | null {
    const parts = jwt.split('.')
    if (parts.length < 2) {
      return null
    }
    let segment = parts[1]
    segment = segment.replace(/-/g, '+').replace(/_/g, '/')
    while (segment.length % 4 !== 0) {
      segment = segment + '='
    }
    try {
      const bytes = JwtPayloadUtils.base64.decodeSync(segment)
      const text = util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeToString(bytes)
      return JSON.parse(text) as Record<string, Object>
    } catch {
      return null
    }
  }
}
