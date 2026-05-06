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
}
