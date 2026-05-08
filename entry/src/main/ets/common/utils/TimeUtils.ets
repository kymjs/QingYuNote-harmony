const ONE_SECOND = 1000

export class TimeUtils {
  static readonly TOLERANCE_MS: number = ONE_SECOND

  static now(): number {
    return Date.now()
  }

  static normalizeRemoteTimestamp(timestamp: number): number {
    if (timestamp <= 0) {
      return 0
    }
    if (timestamp < 10_000_000_000) {
      return timestamp * ONE_SECOND
    }
    return timestamp
  }

  static fromHttpDate(httpDate?: string): number {
    if (!httpDate) {
      return 0
    }
    const parsed = Date.parse(httpDate)
    return Number.isNaN(parsed) ? 0 : parsed
  }

  static compareWithTolerance(left: number, right: number, tolerance: number = TimeUtils.TOLERANCE_MS): number {
    const delta = left - right
    if (Math.abs(delta) <= tolerance) {
      return 0
    }
    return delta > 0 ? 1 : -1
  }

  static format(timestamp: number): string {
    if (timestamp <= 0) {
      return '--'
    }
    const date = new Date(timestamp)
    const month = `${date.getMonth() + 1}`.padStart(2, '0')
    const day = `${date.getDate()}`.padStart(2, '0')
    const hours = `${date.getHours()}`.padStart(2, '0')
    const minutes = `${date.getMinutes()}`.padStart(2, '0')
    return `${month}-${day} ${hours}:${minutes}`
  }

  /**
   * 将毫秒时间戳格式化为 UTC 日历日期 `YYYY-MM-DD`（用于 HTTP Date 对应的「服务器当天」锚点）。
   */
  static formatUtcYmdFromMillis(ms: number): string {
    const u = new Date(ms)
    const y = u.getUTCFullYear()
    const m = u.getUTCMonth() + 1
    const d = u.getUTCDate()
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`)
    return `${y}-${pad(m)}-${pad(d)}`
  }

  /** 在已有 `YYYY-MM-DD` 上增加若干日历月（与 JS Date 溢出规则一致）。 */
  static addCalendarMonthsToYmd(ymd: string, months: number): string {
    const trimmed = ymd.trim()
    if (trimmed.length !== 10 || trimmed.charAt(4) !== '-' || trimmed.charAt(7) !== '-') {
      return trimmed
    }
    const y = Number(trimmed.substring(0, 4))
    const m = Number(trimmed.substring(5, 7))
    const d = Number(trimmed.substring(8, 10))
    if (Number.isNaN(y) || Number.isNaN(m) || Number.isNaN(d)) {
      return trimmed
    }
    const dt = new Date(y, m - 1 + months, d)
    const yy = dt.getFullYear()
    const mm = dt.getMonth() + 1
    const dd = dt.getDate()
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`)
    return `${yy}-${pad(mm)}-${pad(dd)}`
  }
}

