/** Web 内微信读书登录二维码长按保存 / 复制 API Key 通知（供 H5WebContainer javaScriptProxy 调用）。 */
export class WereadQrSaveBridge {
  private saveHandler: (payload: string) => void = () => {
  }
  private keyCopiedHandler: (key: string) => void = () => {
  }

  bind(saveHandler: (payload: string) => void): void {
    this.saveHandler = saveHandler
  }

  bindKeyCopied(handler: (key: string) => void): void {
    this.keyCopiedHandler = handler
  }

  saveQrImage(payload: string): void {
    this.saveHandler(payload)
  }

  /**
   * Web 内点击「复制 API Key」后由 JS 主动调用。
   * @param key  JS 从页面 DOM 抓到的 API Key;为空时表示抓取失败,需走系统剪贴板兜底。
   */
  onApiKeyCopied(key: string): void {
    this.keyCopiedHandler(key ?? '')
  }
}
