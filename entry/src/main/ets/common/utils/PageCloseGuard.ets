import { Logger } from './Logger'

/** 防止连续快速返回导致多次 router.back()（PopPage 后再次 back 可能 ExitToDesktop）。 */
export class PageCloseGuard {
  private closing: boolean = false

  reset(): void {
    this.closing = false
  }

  tryBeginClose(): boolean {
    if (this.closing) {
      return false
    }
    this.closing = true
    return true
  }

  isClosing(): boolean {
    return this.closing
  }

  runBack(back: () => void, logTag?: string): void {
    if (!this.tryBeginClose()) {
      return
    }
    try {
      back()
    } catch (error) {
      if (logTag !== undefined && logTag.length > 0) {
        Logger.warn(logTag, `runBack failed: ${JSON.stringify(error)}`)
      }
    }
  }
}
