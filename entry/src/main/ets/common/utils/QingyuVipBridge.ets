/** VIP H5 ↔ 原生 Bridge（H5WebContainer javaScriptProxy）。 */
export class QingyuVipBridge {
  private payHandler: (planId: string, requestId: string) => void = (_p: string, _r: string) => {
  }
  private closeHandler: () => void = () => {
  }
  private sessionProvider: () => string = () => '{}'

  bindPay(handler: (planId: string, requestId: string) => void): void {
    this.payHandler = handler
  }

  bindClose(handler: () => void): void {
    this.closeHandler = handler
  }

  bindSessionProvider(provider: () => string): void {
    this.sessionProvider = provider
  }

  pay(planId: string, requestId: string): void {
    this.payHandler(planId ?? '', requestId ?? '')
  }

  close(): void {
    this.closeHandler()
  }

  getSession(): string {
    return this.sessionProvider()
  }
}
