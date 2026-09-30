/** 用户反馈 / 我的反馈 H5 ↔ 原生 Bridge（H5WebContainer javaScriptProxy）。 */
export class QingyuFeedbackBridge {
  private closeHandler: () => void = () => {
  }
  private sessionProvider: () => string = () => '{}'
  private latestReplyProvider: () => string = () => '{"type":"latestReply","reply":null}'
  private messageHandler: (action: string) => void = (_action: string) => {
  }

  bindClose(handler: () => void): void {
    this.closeHandler = handler
  }

  bindSessionProvider(provider: () => string): void {
    this.sessionProvider = provider
  }

  bindLatestReplyProvider(provider: () => string): void {
    this.latestReplyProvider = provider
  }

  bindMessageHandler(handler: (action: string) => void): void {
    this.messageHandler = handler
  }

  close(): void {
    this.closeHandler()
  }

  getSession(): string {
    return this.sessionProvider()
  }

  getLatestReply(): string {
    return this.latestReplyProvider()
  }

  postMessage(raw: string): void {
    let action = ''
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>
      action = `${parsed['action'] ?? ''}`.trim()
    } catch (_) {
      return
    }
    if (action === 'close') {
      this.close()
      return
    }
    this.messageHandler(action)
  }
}
