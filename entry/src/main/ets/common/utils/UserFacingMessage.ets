/**
 * 将异常、错误码、接口原文等整理为适合在 Toast 中展示的文案。
 */
export class UserFacingMessage {
  private static readonly AI_ALLOW_LIST: string[] = [
    '笔记正文为空，无法优化',
    '请输入有效链接',
    '未登录或服务不可用',
    'AI 未返回有效内容',
    '语音转文字失败，请稍后重试',
    '语音转文字未返回有效内容',
    '录音文件未找到，请稍后重试',
    '录音格式无法识别，请重新录制',
    '同步失败，请稍后重试'
  ]

  static sanitize(raw: string | undefined | null, fallback: string): string {
    const trimmed = `${raw ?? ''}`.trim()
    if (trimmed.length === 0) {
      return fallback
    }
    if (UserFacingMessage.looksLikeInternal(trimmed)) {
      return fallback
    }
    return trimmed
  }

  static forCatch(error: Object | string | undefined, fallback: string): string {
    if (typeof error === 'string') {
      return UserFacingMessage.sanitize(error, fallback)
    }
    if (error instanceof Error) {
      return UserFacingMessage.sanitize(error.message, fallback)
    }
    const serialized = JSON.stringify(error)
    const raw = serialized.length > 0 && serialized !== '{}' ? serialized : `${error ?? ''}`
    return UserFacingMessage.sanitize(raw, fallback)
  }

  static forAi(raw: string | undefined | null, fallback: string): string {
    const trimmed = `${raw ?? ''}`.trim()
    if (trimmed.length === 0) {
      return fallback
    }
    if (UserFacingMessage.AI_ALLOW_LIST.indexOf(trimmed) >= 0) {
      return trimmed
    }
    return fallback
  }

  static forPaymentVerify(obj: Object | null, fallback: string): string {
    if (obj === null) {
      return fallback
    }
    const r = obj as Record<string, Object>
    const msg = r['message']
    if (typeof msg === 'string') {
      return UserFacingMessage.sanitize(msg, fallback)
    }
    return fallback
  }

  static forSyncNoteFailure(raw: string | undefined | null): string {
    const trimmed = `${raw ?? ''}`.trim()
    if (trimmed.length === 0 || UserFacingMessage.looksLikeInternal(trimmed)) {
      return UserFacingMessage.formatSyncFailure(trimmed)
    }
    if (!UserFacingMessage.looksLikeExceptionText(trimmed)) {
      return trimmed
    }
    return UserFacingMessage.formatSyncFailure(trimmed)
  }

  private static formatSyncFailure(raw: string): string {
    const normalized = raw.toLowerCase()
    if (normalized.includes('authentication')) {
      return '同步失败：账号或密码可能已失效，请检查同步设置'
    }
    if (normalized.includes('qingyu webdav credentials unavailable')) {
      return '同步失败：暂时无法连接轻羽云存储，请稍后重试或检查网络'
    }
    if (normalized.includes('not configured')) {
      return '同步失败：请先完成云服务配置'
    }
    if (normalized.includes('timeout')) {
      return '同步失败：请求超时，请稍后重试'
    }
    if (normalized.includes('100002') || normalized.includes('uri error')
      || normalized.includes('does not exist') || normalized.includes('not exist')) {
      return '同步失败：目标不可用'
    }
    return '同步失败，请稍后重试'
  }

  static looksLikeInternal(s: string): boolean {
    if (UserFacingMessage.looksLikeExceptionText(s)) {
      return true
    }
    const lower = s.toLowerCase()
    if (lower.includes('minimax') || lower.includes('choices') || lower.includes('http/')
      || lower.includes('http ') || lower.startsWith('ai 请求失败') || lower.includes('aliyun')
      || lower.includes('nginx') || lower.includes('client_max_body') || lower.includes('服务端日志')
      || lower.includes('最近解析') || lower.includes('failed with status')
      || lower.includes('credential decrypt') || lower.includes('order_confirm')) {
      return true
    }
    if (/[（(][\w_]{3,}[）)]/.test(s)) {
      return true
    }
    if (/^[a-z][a-z0-9_]+$/.test(lower) && lower.length <= 48) {
      return true
    }
    return false
  }

  private static looksLikeExceptionText(s: string): boolean {
    const lower = s.toLowerCase()
    return lower.includes('exception') || lower.startsWith('error:')
      || lower.includes('dioexception') || lower.includes('stacktrace')
      || lower.includes('authentication failed')
      || (lower.includes('webdav') && lower.includes('failed'))
  }
}
