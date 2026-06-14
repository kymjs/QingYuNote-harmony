/** 印象笔记 Developer Token 页的原生 ↔ Web 桥（供 H5WebContainer javaScriptProxy 调用）。 */
export class YinxiangApiKeyBridge {
  private tokenReadyHandler: (token: string, noteStoreUrl: string) => void = () => {
  }

  bindTokenReady(handler: (token: string, noteStoreUrl: string) => void): void {
    this.tokenReadyHandler = handler
  }

  /**
   * Web 页检测到 Developer Token 与 NoteStore URL 后主动调用。
   * @param token         以 `S=` 开头的 Developer Token
   * @param noteStoreUrl  NoteStore 服务地址（可为空）
   */
  onTokenReady(token: string, noteStoreUrl: string): void {
    this.tokenReadyHandler(token ?? '', noteStoreUrl ?? '')
  }
}
