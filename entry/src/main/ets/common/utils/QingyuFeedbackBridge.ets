/** 用户反馈 H5 ↔ 原生 Bridge（H5WebContainer javaScriptProxy）。 */
export class QingyuFeedbackBridge {
  private closeHandler: () => void = () => {
  }
  private sessionProvider: () => string = () => '{}'

  bindClose(handler: () => void): void {
    this.closeHandler = handler
  }

  bindSessionProvider(provider: () => string): void {
    this.sessionProvider = provider
  }

  close(): void {
    this.closeHandler()
  }

  getSession(): string {
    return this.sessionProvider()
  }
}
