/** 有道云 mopen 申请 API Key 流程的原生 ↔ Web 桥（供 H5WebContainer javaScriptProxy 调用）。 */
export class YoudaoApiKeyBridge {
  private keyCopiedHandler: (key: string) => void = () => {
  }

  bindKeyCopied(handler: (key: string) => void): void {
    this.keyCopiedHandler = handler
  }

  /**
   * Web 内点击「复制 API Key」后由 JS 主动调用。
   * @param key  JS 从页面 DOM 抓到的 API Key;为空时表示抓取失败,需走系统剪贴板兜底。
   */
  onApiKeyCopied(key: string): void {
    this.keyCopiedHandler(key ?? '')
  }
}
